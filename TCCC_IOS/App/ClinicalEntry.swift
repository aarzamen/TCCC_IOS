import Foundation
import TCCCDomain
import TCCCExtractor

/// Operator-entered context is per encounter; unknown strings remain empty.
struct EncounterOperatorMetadata: Codable {
    struct Note: Codable { var timestamp: Date; var text: String }
    var name = ""
    var unit = ""
    var serviceNumber = ""
    var allergies = ""
    var nineLineValues: [Int: String] = [:]
    var notes: [Note] = []
    var radioCallTime: Date?
}

enum ClinicalEntryKind: String, Identifiable, CaseIterable {
    case identity, vitals, assessment, tourniquet, medication, mark, nineLine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .identity: "Casualty details"
        case .vitals: "Record vital signs"
        case .assessment: "Correct assessment"
        case .tourniquet: "Record tourniquet"
        case .medication: "Record medication"
        case .mark: "Mark time / note"
        case .nineLine: "Edit 9-line fields"
        }
    }
}

struct ClinicalEntryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ManualVitalsDraft {
    var hr = "", systolic = "", diastolic = "", spo2 = "", rr = "", avpu = "", pain = ""
    func reading(timestamp: Date = Date()) throws -> AppState.SectionCReading {
        try validated(timestamp: timestamp).reading
    }
    func writes() throws -> [PatientStateFieldWrite] { try validated().writes }

    /// One parse supplies both engine writes and the observation exported in §C.
    func validated(timestamp: Date = Date()) throws -> (writes: [PatientStateFieldWrite], reading: AppState.SectionCReading) {
        func value(_ text: String, _ label: String, _ range: ClosedRange<Int>) throws -> Int? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard let number = Int(text), range.contains(number) else {
                throw ClinicalEntryError(message: "\(label) must be a whole number from \(range.lowerBound) to \(range.upperBound).")
            }
            return number
        }
        let pulse = try value(hr, "Pulse", 0...300)
        let oxygen = try value(spo2, "SpO₂", 0...100)
        let respirations = try value(rr, "Respirations", 0...80)
        let sys = try value(systolic, "Systolic pressure", 0...300)
        let dia = try value(diastolic, "Diastolic pressure", 0...250)
        let painValue = try value(pain, "Pain", 0...10).map(String.init)
        let consciousness = avpu.trimmingCharacters(in: .whitespacesAndNewlines)
        var pressure: BloodPressure?
        if sys != nil || dia != nil {
            guard let sys, let dia, sys >= dia else {
                throw ClinicalEntryError(message: "Enter both pressures with systolic at least diastolic.")
            }
            pressure = BloodPressure(systolic: sys, diastolic: dia)
        }
        var writes: [PatientStateFieldWrite] = []
        if let pulse { writes.append(.heartRate(pulse)) }
        if let oxygen { writes.append(.spo2(oxygen)) }
        if let respirations { writes.append(.respiratoryRate(respirations)) }
        if let pressure { writes.append(.bloodPressure(systolic: pressure.systolic, diastolic: pressure.diastolic, palpated: false)) }
        if !consciousness.isEmpty { writes.append(.consciousness(consciousness)) }
        if let painValue { writes.append(.pain(painValue)) }
        guard !writes.isEmpty else { throw ClinicalEntryError(message: "Enter at least one observation. Blank fields leave existing observations unchanged.") }
        let reading = AppState.SectionCReading(timestamp: timestamp,
            vitals: Vitals(hr: pulse, bp: pressure, spo2: oxygen, rr: respirations),
            avpu: consciousness.isEmpty ? nil : consciousness, pain: painValue)
        return (writes, reading)
    }

}


/// Preserve fields the operator did not edit, and reject changed source values
/// in edited fields. All comparisons and writes share one engine actor turn.
struct ManualAssessmentDraft: Sendable {
    var mechanism: String
    var classification: String
    var injuries: String
    private let originalMechanism: String
    private let originalClassification: String
    private let originalInjuries: String

    init(patient: PatientState?) {
        mechanism = patient?.mechanismOfInjury ?? ""
        classification = patient?.classification?.rawValue ?? ""
        injuries = patient?.injuries.joined(separator: "\n") ?? ""
        originalMechanism = mechanism
        originalClassification = classification
        originalInjuries = injuries
    }

    func apply(to engine: isolated PatientStateEngine, timestamp: Date = Date()) throws {
        let current = engine.snapshot(of: "PATIENT_1")
        var writes: [PatientStateFieldWrite] = []
        func check(_ current: String, _ original: String, _ field: String) throws {
            guard current == original else {
                throw ClinicalEntryError(message: "\(field) changed while this editor was open. Close and reopen it to review the new value before correcting it.")
            }
        }
        if mechanism != originalMechanism {
            try check(current?.mechanismOfInjury ?? "", originalMechanism, "Mechanism")
            let value = mechanism.trimmingCharacters(in: .whitespacesAndNewlines)
            writes.append(.mechanismOfInjury(value.isEmpty ? nil : value))
        }
        if classification != originalClassification {
            try check(current?.classification?.rawValue ?? "", originalClassification, "Precedence")
            writes.append(.classification(Classification(rawValue: classification)))
        }
        if injuries != originalInjuries {
            try check(current?.injuries.joined(separator: "\n") ?? "", originalInjuries, "Injuries")
            let values = injuries.split(separator: "\n").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            writes.append(.setInjuries(values))
        }
        // Do not emit any mutation until every edited field passes its check.
        for write in writes {
            engine.recordOperatorAcceptedFact(write: write, factId: nil, domain: "manual",
                field: "operator assessment correction", rawValue: nil, to: "PATIENT_1", timestamp: timestamp)
        }
    }
}

extension AppState {
    func saveOperatorMetadata(_ metadata: EncounterOperatorMetadata, encounter: UUID) async throws {
        guard encounterIdentity == encounter, let store = encounterStore,
              let directory = await store.activeDirectoryName(), encounterIdentity == encounter else {
            throw ClinicalEntryError(message: "The encounter changed or storage is unavailable. Reopen the editor.")
        }
        try await store.saveOperatorMetadata(JSONEncoder().encode(metadata), expectedDirectory: directory)
        guard encounterIdentity == encounter else { throw ClinicalEntryError(message: "The encounter changed. The previous encounter retains the edit.") }
        operatorMetadata = metadata
        casualtyName = metadata.name; casualtyUnit = metadata.unit
        casualtyServiceNumberMasked = metadata.serviceNumber; casualtyAllergies = metadata.allergies
        lastMedevacTransmitTime = metadata.radioCallTime
    }

    func saveOperatorNote(text: String) async throws {
        let token = encounterIdentity
        var metadata = operatorMetadata
        let note = EncounterOperatorMetadata.Note(timestamp: Date(), text: text)
        metadata.notes.append(note)
        try await saveOperatorMetadata(metadata, encounter: token)
        transcript.append(TranscriptLine(speaker: .system, text: note.text, timestamp: note.timestamp))
    }

    func applyClinicalEntry(_ writes: [PatientStateFieldWrite], encounter: UUID, recordsVitals: Bool = false) async throws {
        guard encounterIdentity == encounter else { throw ClinicalEntryError(message: "Encounter changed. Reopen the editor.") }
        let target = engine
        await settleCaptureBeforeOperatorEntry()
        guard encounterIdentity == encounter else { throw ClinicalEntryError(message: "Encounter changed. Reopen the editor.") }
        let now = Date()
        for write in writes {
            await target.recordOperatorAcceptedFact(write: write, factId: nil, domain: "manual",
                field: "operator entry", rawValue: nil, to: "PATIENT_1", timestamp: now)
        }
        guard encounterIdentity == encounter else { throw ClinicalEntryError(message: "Encounter changed during the edit. Review the previous record.") }
        await refreshPatientSnapshot(recordVitals: !recordsVitals)
    }

    func applyAssessmentEntry(_ draft: ManualAssessmentDraft, encounter: UUID) async throws {
        guard encounterIdentity == encounter else { throw ClinicalEntryError(message: "Encounter changed. Reopen the editor.") }
        let target = engine
        await settleCaptureBeforeOperatorEntry()
        guard encounterIdentity == encounter else { throw ClinicalEntryError(message: "Encounter changed. Reopen the editor.") }
        try await draft.apply(to: target)
        guard encounterIdentity == encounter else { throw ClinicalEntryError(message: "Encounter changed during the edit. Review the previous record.") }
        await refreshPatientSnapshot()
    }

    func verifyClinicalEntrySaved(encounter: UUID) async throws {
        guard encounterIdentity == encounter, encounterStore != nil else { throw ClinicalEntryError(message: "Encounter changed or storage unavailable.") }
        await persistNewEvents()
        guard await engine.newEvents(since: persistedCursor).isEmpty else {
            throw ClinicalEntryError(message: "Edit is visible in memory but storage failed. Retry Save before leaving.")
        }
    }
}
