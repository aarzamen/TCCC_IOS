import XCTest
import TCCCDomain
@testable import TCCCExtractor

/// End-to-end tests that run the full `PatientStateEngine.standard()` pipeline
/// (MOI + 9 extractors) against the four narrative scenario fixtures.
///
/// Per-extractor unit tests live in their own files. These tests verify that
/// the wired-up dispatch order, sentence tokenization, spoken-number
/// normalization, negation detection, and patient switching all compose
/// correctly into the snapshot a UI would render.
///
/// Assertions favor robustness over precision: vitals are checked exactly
/// (numeric forms must match), text fields are checked for non-nil and
/// substring presence (the agent ports may format strings differently than
/// the Python source).
final class EndToEndScenarioTests: XCTestCase {

    private func loadScenario(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "scenarios"),
            "Scenario fixture \(name).txt not found in test bundle"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Scenario 1: GSW thigh, single patient, urgent

    func testScenario1ProducesSinglePatient() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_1_gsw_thigh")
        await engine.processTranscript(text)
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertNotNil(snapshot["PATIENT_1"])
    }

    func testScenario1HasGSWMechanism() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_1_gsw_thigh")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        XCTAssertEqual(patient.mechanismOfInjury, "GSW")
    }

    func testScenario1HasTourniquetAndAirway() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_1_gsw_thigh")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        XCTAssertNotNil(patient.march.hemorrhageIntervention,
                        "Tourniquet should be recorded in hemorrhage intervention")
        XCTAssertNotNil(patient.march.airwayStatus,
                        "Airway status should be set after 'airway is patent'")
    }

    func testScenario1Vitals() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_1_gsw_thigh")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        // "heart rate one ten, blood pressure ninety over sixty, pulse ox ninety-six percent, respiratory rate eighteen"
        XCTAssertEqual(patient.vitals.hr, 110, "HR 110 from 'one ten'")
        XCTAssertEqual(patient.vitals.bp?.systolic, 90, "Systolic 90 from 'ninety over sixty'")
        XCTAssertEqual(patient.vitals.bp?.diastolic, 60, "Diastolic 60 from 'ninety over sixty'")
        XCTAssertEqual(patient.vitals.spo2, 96, "SpO2 96 from 'ninety-six percent'")
        XCTAssertEqual(patient.vitals.rr, 18, "RR 18 from 'respiratory rate eighteen'")
    }

    // MARK: - Scenario 2: IED blast, two patients

    func testScenario2ProducesTwoPatients() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_2_blast_multi")
        await engine.processTranscript(text)
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.count, 2, "Should detect both casualties")
        XCTAssertNotNil(snapshot["PATIENT_1"])
        XCTAssertNotNil(snapshot["PATIENT_2"])
    }

    func testScenario2Patient1HasBlastMOIAndBilateralBleeding() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_2_blast_multi")
        await engine.processTranscript(text)
        let snapshotP1 = await engine.snapshot(of: "PATIENT_1")
        let p1 = try XCTUnwrap(snapshotP1)
        XCTAssertEqual(p1.mechanismOfInjury, "IED blast")
        XCTAssertNotNil(p1.march.hemorrhageIntervention,
                        "Bilateral tourniquets should be recorded")
        XCTAssertNotNil(p1.march.airwayIntervention,
                        "NPA should be recorded as airway intervention")
    }

    func testScenario2Patient2IsSeparate() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_2_blast_multi")
        await engine.processTranscript(text)
        let snapshotP2 = await engine.snapshot(of: "PATIENT_2")
        let p2 = try XCTUnwrap(snapshotP2)
        // Patient 2 is the laceration / pressure-dressing casualty.
        // Should not have the bilateral tourniquet of patient 1.
        XCTAssertNil(p2.march.hemorrhageIntervention?.lowercased().firstIndex(of: "t").flatMap { _ in
            p2.march.hemorrhageIntervention?.lowercased().contains("tourniquet") == true ? "x" : nil
        }, "P2 should not have tourniquet finding")
    }

    func testScenario2Patient2ClassifiedPriority() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_2_blast_multi")
        await engine.processTranscript(text)
        let snapshotP2 = await engine.snapshot(of: "PATIENT_2")
        let p2 = try XCTUnwrap(snapshotP2)
        XCTAssertEqual(p2.classification, .priority,
                       "Sentence 'this is a priority patient' should classify P2 as priority")
    }

    // MARK: - Scenario 3: routine knife laceration

    func testScenario3SinglePatientKnifeLaceration() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_3_mre_laceration")
        await engine.processTranscript(text)
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.count, 1)
        let patient = try XCTUnwrap(snapshot["PATIENT_1"])
        XCTAssertEqual(patient.mechanismOfInjury, "Penetrating trauma")
    }

    func testScenario3Vitals() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_3_mre_laceration")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        // "heart rate seventy-two, blood pressure one twenty over seventy-eight, pulse ox ninety-nine, respiratory rate fourteen"
        XCTAssertEqual(patient.vitals.hr, 72)
        XCTAssertEqual(patient.vitals.bp?.systolic, 120)
        XCTAssertEqual(patient.vitals.bp?.diastolic, 78)
        XCTAssertEqual(patient.vitals.spo2, 99)
        XCTAssertEqual(patient.vitals.rr, 14)
    }

    func testScenario3ClassifiedRoutine() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_3_mre_laceration")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        XCTAssertEqual(patient.classification, .routine,
                       "Sentence 'this is a routine casualty' should classify as routine")
    }

    // MARK: - Scenario 4: femur fracture, urgent

    func testScenario4HasFallMOI() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_4_femur_fracture")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        XCTAssertEqual(patient.mechanismOfInjury, "Fall",
                       "'just fell' should match the fall MOI pattern")
    }

    func testScenario4HemorrhageIdentifiedDespiteContractionNegation() async throws {
        // Python parity: state.py's `hemorrhage_patterns["negative"]` regex does
        // not include the `don't` contraction in its negation alternation, so
        // "I don't see any external bleeding" still matches the positive
        // `bleed|blood|hemorrhag` pattern and flags hemorrhage. Faithful Swift
        // port preserves this. If the Python upstream adds `don't|doesn't` to
        // the negation regex, mirror it and flip this assertion.
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_4_femur_fracture")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        XCTAssertTrue(patient.march.hemorrhageIdentified,
                      "Known Python parity: 'don't' is not caught by the negation regex.")
    }

    func testScenario4FemurFractureRecordedAsInjury() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_4_femur_fracture")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        let injuriesText = patient.injuries.joined(separator: " | ").lowercased()
        XCTAssertTrue(
            injuriesText.contains("femur") || injuriesText.contains("fracture"),
            "Femur fracture should appear in injuries list — got \(patient.injuries)"
        )
    }

    func testScenario4Vitals() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_4_femur_fracture")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        // "heart rate one hundred and five, blood pressure one hundred over sixty-eight, pulse ox ninety-seven, respiratory rate twenty"
        XCTAssertEqual(patient.vitals.hr, 105)
        XCTAssertEqual(patient.vitals.bp?.systolic, 100)
        XCTAssertEqual(patient.vitals.bp?.diastolic, 68)
        XCTAssertEqual(patient.vitals.spo2, 97)
        XCTAssertEqual(patient.vitals.rr, 20)
    }

    func testScenario4ClassifiedUrgent() async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_4_femur_fracture")
        await engine.processTranscript(text)
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        XCTAssertEqual(patient.classification, .urgent,
                       "Sentence 'this is an urgent casualty' should classify as urgent")
    }

    // MARK: - Multi-chunk session

    func testIncrementalChunksAccumulate() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("GSW upper right thigh.")
        await engine.processTranscript("Heart rate one ten.")
        await engine.processTranscript("Blood pressure ninety over sixty.")
        let snapshotOfP1 = await engine.snapshot(of: "PATIENT_1")
        let patient = try XCTUnwrap(snapshotOfP1)
        XCTAssertEqual(patient.mechanismOfInjury, "GSW")
        XCTAssertEqual(patient.vitals.hr, 110)
        XCTAssertEqual(patient.vitals.bp?.systolic, 90)
        XCTAssertEqual(patient.vitals.bp?.diastolic, 60)
    }
}
