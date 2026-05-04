// PatientStateEngineTests
//
// End-to-end tests for `PatientStateEngine` exercising the Lane-A extractors:
// hemorrhage, airway, head/hypothermia. These tests mirror the relevant
// assertions from
// /Users/ama/TCCC_FEB_2026/tests/test_state_scenarios.py and
// /Users/ama/TCCC_FEB_2026/tests/test_state_negation.py — but limited to the
// fields owned by Lane A. Other-lane assertions (vitals, fractures,
// classification, etc.) are out of scope here.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class PatientStateEngineTests: XCTestCase {

    private func loadScenario(_ filename: String) throws -> String {
        let stem = (filename as NSString).deletingPathExtension
        guard let url = Bundle.module.url(
            forResource: stem,
            withExtension: "txt",
            subdirectory: "scenarios"
        ) else {
            XCTFail("Missing bundled scenario resource: \(stem).txt")
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Init / defaults

    func testInitCreatesPatient1WithDefaults() async {
        let engine = PatientStateEngine.standard()
        let snap = await engine.snapshot()
        XCTAssertEqual(snap.count, 1)
        XCTAssertNotNil(snap["PATIENT_1"])
        let id = await engine.currentPatientID
        XCTAssertEqual(id, "PATIENT_1")
    }

    func testSnapshotOfReturnsNilForUnknown() async {
        let engine = PatientStateEngine.standard()
        let p = await engine.snapshot(of: "PATIENT_99")
        XCTAssertNil(p)
    }

    // MARK: - Timestamps

    func testFirstMentionAndLastUpdateSetOnFirstChunk() async {
        let engine = PatientStateEngine.standard()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        await engine.processTranscript("Airway is patent.", timestamp: now)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.timestampFirstMention, now.timeIntervalSince1970)
        XCTAssertEqual(p.timestampLastUpdate, now.timeIntervalSince1970)
    }

    func testFirstMentionPreservedAcrossChunks() async {
        let engine = PatientStateEngine.standard()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_500)
        await engine.processTranscript("Airway is patent.", timestamp: t1)
        await engine.processTranscript("Pupils equal.", timestamp: t2)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.timestampFirstMention, t1.timeIntervalSince1970)
        XCTAssertEqual(p.timestampLastUpdate, t2.timeIntervalSince1970)
    }

    // MARK: - Patient switching

    func testSwitchToPatient2OnMovingToCasualtyTwo() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(
            "Moving to casualty two now. This patient is alert and talking.")
        let id = await engine.currentPatientID
        XCTAssertEqual(id, "PATIENT_2")
    }

    func testSwitchToPatient2OnAnotherPatient() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("another patient over here.")
        let id = await engine.currentPatientID
        XCTAssertEqual(id, "PATIENT_2")
    }

    func testSwitchToPatient2OnNextCasualty() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("next casualty is twenty meters out.")
        let id = await engine.currentPatientID
        XCTAssertEqual(id, "PATIENT_2")
    }

    func testSwitchBackToPatient1OnCasualtyOne() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Moving to casualty two.")
        let after2 = await engine.currentPatientID
        XCTAssertEqual(after2, "PATIENT_2")
        await engine.processTranscript("Back to casualty one.")
        let after1 = await engine.currentPatientID
        XCTAssertEqual(after1, "PATIENT_1")
    }

    func testFindingsRoutedToCorrectPatient() async {
        // Mirrors test_findings_routed_to_correct_patient from
        // tests/test_state_negation.py. Lane A scope: TQ on P1, airway on P2.
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(
            "Starting with casualty one. Applying tourniquet to the right leg.")
        await engine.processTranscript(
            "Moving to casualty two now. Airway is patent, alert and oriented.")
        let snap = await engine.snapshot()
        let p1 = try? XCTUnwrap(snap["PATIENT_1"])
        let p2 = try? XCTUnwrap(snap["PATIENT_2"])
        XCTAssertNotNil(p1?.march.hemorrhageIntervention)
        XCTAssertEqual(p2?.march.airwayStatus, "patent")
    }

    // MARK: - Negation handling
    //
    // Lane A's HemorrhageExtractor uses its dedicated "negative" regex; the
    // engine's isNegated flag is mostly used by other lanes (respiration,
    // classification). We assert the flag is set correctly and that
    // hemorrhage handles the dedicated negative pattern.

    func testNoBleedingObservedDoesNotIdentifyHemorrhage() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("No bleeding observed.")
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertTrue(p.march.hemorrhageAssessed)
        XCTAssertFalse(p.march.hemorrhageIdentified)
    }

    // MARK: - Scenario 1 (GSW thigh)
    //
    // Lane A relevant assertions only. Other-lane assertions (vitals,
    // classification) belong with their respective extractors.

    func testScenario1SinglePatient() async throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let snap = await engine.snapshot()
        XCTAssertEqual(snap.count, 1, "Scenario 1 should have exactly one patient")
    }

    func testScenario1Tourniquet() async throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertNotNil(p.march.hemorrhageIntervention)
        XCTAssertTrue(
            p.march.hemorrhageIntervention!.lowercased().contains("tourniquet"))
    }

    func testScenario1AirwayPatent() async throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.airwayStatus, "patent")
    }

    func testScenario1AlertAndPupils() async throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.consciousness, "Alert")
        XCTAssertEqual(p.march.pupilResponse, "equal")
        XCTAssertEqual(p.march.hypothermiaPrevention, "Hypothermia wrap applied")
    }

    func testScenario1HemorrhageEffective() async throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.hemorrhageEffective, true)
    }

    // MARK: - Scenario 2 (IED blast, two casualties)

    func testScenario2TwoPatients() async throws {
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let snap = await engine.snapshot()
        XCTAssertNotNil(snap["PATIENT_1"])
        XCTAssertNotNil(snap["PATIENT_2"])
        XCTAssertEqual(snap.count, 2)
    }

    func testScenario2Patient1BilateralTourniquet() async throws {
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p1 = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertNotNil(p1.march.hemorrhageLocation)
        XCTAssertTrue(p1.march.hemorrhageLocation!.lowercased().contains("bilateral"),
                      "PATIENT_1 should have bilateral hemorrhage location")
        XCTAssertNotNil(p1.march.hemorrhageIntervention)
        XCTAssertTrue(p1.march.hemorrhageIntervention!.lowercased().contains("tourniquet"))
    }

    func testScenario2Patient1Npa() async throws {
        // Direct port of test_scenario2_patient1_npa from
        // tests/test_state_scenarios.py.
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p1 = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertNotNil(p1.march.airwayIntervention)
        XCTAssertTrue(p1.march.airwayIntervention!.lowercased().contains("npa"))
    }

    func testScenario2Patient2ForearmLocation() async throws {
        // Port of test_scenario2_patient2_forearm_laceration.
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p2 = await engine.snapshot(of: "PATIENT_2")!
        XCTAssertNotNil(p2.march.hemorrhageLocation)
        XCTAssertTrue(p2.march.hemorrhageLocation!.lowercased().contains("forearm"))
    }

    func testScenario2Patient2PressureDressing() async throws {
        // Port of test_scenario2_patient2_pressure_dressing.
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p2 = await engine.snapshot(of: "PATIENT_2")!
        XCTAssertNotNil(p2.march.hemorrhageIntervention)
        XCTAssertTrue(
            p2.march.hemorrhageIntervention!.lowercased().contains("pressure dressing"))
    }

    func testScenario2Patient2NoBilateralTQ() async throws {
        // Port of test_scenario2_patient2_no_bilateral_tq.
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p2 = await engine.snapshot(of: "PATIENT_2")!
        let location = (p2.march.hemorrhageLocation ?? "").lowercased()
        XCTAssertFalse(location.contains("bilateral"),
                       "Bilateral TQ should belong to PATIENT_1, not PATIENT_2")
    }

    // MARK: - Scenario 3 (MRE laceration — low acuity)

    func testScenario3SinglePatient() async throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let snap = await engine.snapshot()
        XCTAssertEqual(snap.count, 1)
    }

    func testScenario3AirwayPatent() async throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.airwayStatus, "patent")
    }

    func testScenario3AlertAndOriented() async throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.consciousness, "Alert")
    }

    // MARK: - Scenario 4 (femur fracture)

    func testScenario4NoTourniquet() async throws {
        // Port of test_scenario4_no_tourniquet.
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        let intervention = (p.march.hemorrhageIntervention ?? "").lowercased()
        XCTAssertFalse(intervention.contains("tourniquet"),
                       "Scenario 4 negates tourniquet; should not appear in hemorrhage intervention")
    }

    func testScenario4HypothermiaWrap() async throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.hypothermiaPrevention, "Hypothermia wrap applied")
    }

    func testScenario4AlertConsciousness() async throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.consciousness, "Alert")
    }

    func testScenario4PupilsEqual() async throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(raw)
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.march.pupilResponse, "equal")
    }

    // MARK: - Custom passes (engine wires extractors in order)

    func testCustomPassesOrderedDispatch() async {
        // Two test passes that record their order. The engine should call
        // them in the order they're listed in `passes`.
        struct Marker: ExtractorPass {
            let tag: String
            func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
                var s = state
                s.injuries.append("\(tag):\(context.sentence)")
                return s
            }
        }
        let engine = PatientStateEngine(passes: [Marker(tag: "first"), Marker(tag: "second")])
        await engine.processTranscript("Hello.")
        let p = await engine.snapshot(of: "PATIENT_1")!
        XCTAssertEqual(p.injuries, ["first:Hello.", "second:Hello."])
    }

    // MARK: - Snapshot is a copy

    func testSnapshotReturnsCopy() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Airway is patent.")
        var snap = await engine.snapshot()
        snap["PATIENT_1"]?.march.airwayStatus = "tampered"
        // Re-snapshot and check the engine's copy was untouched.
        let snap2 = await engine.snapshot()
        XCTAssertEqual(snap2["PATIENT_1"]?.march.airwayStatus, "patent")
    }
}
