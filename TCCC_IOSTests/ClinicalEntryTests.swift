import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class ClinicalEntryTests: XCTestCase {
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
