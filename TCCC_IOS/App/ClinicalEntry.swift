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
        _ = try writes()
        let bp = Int(systolic).flatMap { sys in Int(diastolic).map { BloodPressure(systolic: sys, diastolic: $0) } }
        return .init(timestamp: timestamp,
            vitals: Vitals(hr: Int(hr), bp: bp, spo2: Int(spo2), rr: Int(rr)),
            avpu: avpu.isEmpty ? nil : avpu, pain: pain.isEmpty ? nil : pain)
    }
    func writes() throws -> [PatientStateFieldWrite] {
        var writes: [PatientStateFieldWrite] = []
        func value(_ text: String, _ label: String, _ range: ClosedRange<Int>) throws -> Int? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard let number = Int(text), range.contains(number) else {
                throw ClinicalEntryError(message: "\(label) must be a whole number from \(range.lowerBound) to \(range.upperBound).")
            }
            return number
        }
        if let x = try value(hr, "Pulse", 0...300) { writes.append(.heartRate(x)) }
        if let x = try value(spo2, "SpO₂", 0...100) { writes.append(.spo2(x)) }
        if let x = try value(rr, "Respirations", 0...80) { writes.append(.respiratoryRate(x)) }
        let sys = try value(systolic, "Systolic pressure", 0...300)
        let dia = try value(diastolic, "Diastolic pressure", 0...250)
        if sys != nil || dia != nil {
            guard let sys, let dia, sys >= dia else {
                throw ClinicalEntryError(message: "Enter both pressures with systolic at least diastolic.")
            }
            writes.append(.bloodPressure(systolic: sys, diastolic: dia, palpated: false))
        }
        if !avpu.isEmpty { writes.append(.consciousness(avpu)) }
        if let x = try value(pain, "Pain", 0...10) { writes.append(.pain(String(x))) }
        guard !writes.isEmpty else { throw ClinicalEntryError(message: "Enter at least one observation. Blank fields leave existing observations unchanged.") }
        return writes
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

    func verifyClinicalEntrySaved(encounter: UUID) async throws {
        guard encounterIdentity == encounter, encounterStore != nil else { throw ClinicalEntryError(message: "Encounter changed or storage unavailable.") }
        await persistNewEvents()
        guard await engine.newEvents(since: persistedCursor).isEmpty else {
            throw ClinicalEntryError(message: "Edit is visible in memory but storage failed. Retry Save before leaving.")
        }
    }
}
