import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class ClinicalEntryTests: XCTestCase {
    func testWhitespaceVitalsUseTheSameNormalizedValuesInFactsAndExports() throws {
        var draft = ManualVitalsDraft()
        draft.hr = " 92\n"; draft.systolic = " 120 "; draft.diastolic = "80\t"
        draft.spo2 = " 98 "; draft.rr = " 18 "; draft.avpu = " Alert "; draft.pain = " 07 "
        let reading = try draft.reading(timestamp: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(reading.vitals, Vitals(hr: 92, bp: BloodPressure(systolic: 120, diastolic: 80), spo2: 98, rr: 18))
        XCTAssertEqual(reading.avpu, "Alert")
        XCTAssertEqual(reading.pain, "7")
        XCTAssertEqual(try draft.writes(), [.heartRate(92), .spo2(98), .respiratoryRate(18),
            .bloodPressure(systolic: 120, diastolic: 80, palpated: false), .consciousness("Alert"), .pain("7")])
        XCTAssertEqual(reading.toDD1380().pulse, "92")
        XCTAssertTrue(HandoffExports.vitalsCSV(readings: [reading]).contains(",92,120,80,false,98,18,,,,Alert,7"))
    }

    func testWhitespaceOnlyVitalsRemainUnentered() {
        var draft = ManualVitalsDraft(); draft.hr = " \n"; draft.avpu = " "
        XCTAssertThrowsError(try draft.reading())
    }

    func testAssessmentPrecedenceEditPreservesNewUntouchedEvidence() async throws {
        let engine = PatientStateEngine.standard()
        var draft = ManualAssessmentDraft(patient: nil)
        draft.classification = Classification.priority.rawValue
        await engine.recordOperatorAcceptedFact(write: .mechanismOfInjury("New mechanism"), factId: nil,
            domain: "test", field: "mechanism", rawValue: nil, to: "PATIENT_1")
        await engine.recordOperatorAcceptedFact(write: .setInjuries(["New recorded injury"]), factId: nil,
            domain: "test", field: "injuries", rawValue: nil, to: "PATIENT_1")
        try await draft.apply(to: engine)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.classification, .priority)
        XCTAssertEqual(patient?.mechanismOfInjury, "New mechanism")
        XCTAssertEqual(patient?.injuries, ["New recorded injury"])
    }

    func testAssessmentConflictingEditedFieldRejectsWholePatch() async throws {
        let engine = PatientStateEngine.standard()
        var draft = ManualAssessmentDraft(patient: nil)
        draft.mechanism = "Operator mechanism"
        draft.classification = Classification.priority.rawValue
        await engine.recordOperatorAcceptedFact(write: .mechanismOfInjury("New captured mechanism"), factId: nil,
            domain: "test", field: "mechanism", rawValue: nil, to: "PATIENT_1")
        do { try await draft.apply(to: engine); XCTFail("A newer value in an edited field must require review") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Mechanism")) }
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.mechanismOfInjury, "New captured mechanism")
        XCTAssertNil(patient?.classification, "No partial patch may precede conflict detection")
    }

    func testExplicitAssessmentClearOnlyClearsTheEditedField() async throws {
        let engine = PatientStateEngine.standard()
        await engine.recordOperatorAcceptedFact(write: .mechanismOfInjury("Old mechanism"), factId: nil,
            domain: "test", field: "mechanism", rawValue: nil, to: "PATIENT_1")
        let initial = await engine.snapshot(of: "PATIENT_1")
        var draft = ManualAssessmentDraft(patient: initial)
        draft.mechanism = ""
        await engine.recordOperatorAcceptedFact(write: .classification(.urgent), factId: nil,
            domain: "test", field: "classification", rawValue: nil, to: "PATIENT_1")
        try await draft.apply(to: engine)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertNil(patient?.mechanismOfInjury)
        XCTAssertEqual(patient?.classification, .urgent)
    }

    func testRepeatedManualReadingsRetainBothTimesWithoutCarriedFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(); state.documentsURL = root
        await state.load()
        var draft = ManualVitalsDraft(); draft.hr = "92"
        let first = try draft.reading(timestamp: Date(timeIntervalSince1970: 100))
        let second = try draft.reading(timestamp: Date(timeIntervalSince1970: 200))
        try await state.saveManualReading(first, encounter: state.encounterIdentity)
        try await state.saveManualReading(second, encounter: state.encounterIdentity)
        XCTAssertEqual(state.vitalsLog.count, 2)
        XCTAssertEqual(state.vitalsLog.map(\.timestamp), [first.timestamp, second.timestamp])
        XCTAssertNil(second.vitals.bp)
        XCTAssertNil(second.avpu)
        try await state.applyClinicalEntry([.heartRate(92)], encounter: state.encounterIdentity, recordsVitals: true)
        await state.refreshPatientSnapshot()
        XCTAssertEqual(state.vitalsLog.count, 2, "Refreshing unchanged engine values must not stamp a new combined reading")
    }

    func testBlankVitalsDoNotClearKnownValues() throws {
        var draft = ManualVitalsDraft(); draft.hr = "92"
        XCTAssertEqual(try draft.writes(), [.heartRate(92)])
        draft.spo2 = "101"
        XCTAssertThrowsError(try draft.writes())
    }

    func testPartialBloodPressureCannotBecomeRecordedReading() {
        var draft = ManualVitalsDraft(); draft.systolic = "120"
        XCTAssertThrowsError(try draft.writes())
        draft.diastolic = "80"
        XCTAssertEqual(try draft.writes(), [.bloodPressure(systolic: 120, diastolic: 80, palpated: false)])
    }

    func testManualInterventionAndCorrectionsReplayExactly() async throws {
        let engine = PatientStateEngine.standard()
        let intervention = Intervention(timestamp: Date(timeIntervalSince1970: 100), kind: .medication, description: "Operator supplied medication and dose")
        let writes: [PatientStateFieldWrite] = [.mechanismOfInjury("Fall"), .classification(.priority), .setInjuries(["Left forearm injury"]), .appendIntervention(intervention)]
        for write in writes { await engine.recordOperatorAcceptedFact(write: write, factId: nil, domain: "manual", field: "entry", rawValue: nil, to: "PATIENT_1") }
        let before = await engine.snapshot()
        let log = await engine.snapshotLog()
        let encoded = try JSONEncoder().encode(log)
        let restored = PatientStateEngine.standard()
        try await restored.restore(JSONDecoder().decode(EncounterLog.self, from: encoded))
        let after = await restored.snapshot()
        XCTAssertEqual(before, after)
        XCTAssertEqual(after["PATIENT_1"]?.interventions, [intervention])
    }

    func testOperatorDetailsRestoreWithoutLeakingIntoNextEncounter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EncounterStore(baseURL: root)
        try await store.startNewCasualty(id: "C-01", startUnix: 1)
        let key = await store.activeDirectoryName()!
        var details = EncounterOperatorMetadata(); details.name = "SYNTHETIC TEST"; details.nineLineValues[6] = "operator entered"
        try await store.saveOperatorMetadata(JSONEncoder().encode(details), expectedDirectory: key)
        let restored = try JSONDecoder().decode(EncounterOperatorMetadata.self, from: await store.loadOperatorMetadata()!)
        XCTAssertEqual(restored.name, details.name)
        try await store.archiveActive(endedUnix: 2)
        try await store.startNewCasualty(id: "C-01", startUnix: 2)
        let next = await store.loadOperatorMetadata()
        XCTAssertNil(next)
        do {
            try await store.saveOperatorMetadata(JSONEncoder().encode(details), expectedDirectory: key)
            XCTFail("Stale editor must not write into the next encounter")
        } catch { }
    }
}
