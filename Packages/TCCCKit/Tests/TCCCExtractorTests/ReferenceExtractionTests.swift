import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class ReferenceExtractionTests: XCTestCase {
    func testAuthoredValdezReferenceExtractsAllEightExpectedFacts() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let reference = try String(contentsOf: root.appendingPathComponent("TCCC_IOS/DevTools/Fixtures/valdez_alley.txt"), encoding: .utf8)
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(reference)
        let patients = await engine.snapshot()
        let patient = try XCTUnwrap(patients["PATIENT_1"])
        XCTAssertEqual(patient.vitals.hr, 110)
        XCTAssertEqual(patient.vitals.bp?.systolic, 100)
        XCTAssertEqual(patient.vitals.bp?.diastolic, 65)
        XCTAssertEqual(patient.vitals.rr, 22)
        XCTAssertEqual(patient.vitals.spo2, 97)
        let interventions = patient.interventions.map(\.description).joined(separator: "; ").lowercased()
        for fact in ["tourniquet", "tranexamic", "ketamine", "gauze"] {
            XCTAssertTrue(interventions.contains(fact), "Missing \(fact) from exact authored reference")
        }
    }

    func testLaterCaptureChunkUpdatesAllFourVitalsAndReplays() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("HR 120, RR 28, BP 90/60, SpO2 95.")
        await engine.processTranscript("HR 110, RR 22, BP 100/65, SpO2 97.")
        let snapshot = await engine.snapshot()
        let patient = try XCTUnwrap(snapshot["PATIENT_1"])
        XCTAssertEqual(patient.vitals.hr, 110)
        XCTAssertEqual(patient.vitals.rr, 22)
        XCTAssertEqual(patient.vitals.bp?.systolic, 100)
        XCTAssertEqual(patient.vitals.bp?.diastolic, 65)
        XCTAssertEqual(patient.vitals.spo2, 97)
        let log = await engine.log
        let restored = PatientStateEngine.standard()
        await restored.restore(log)
        let replayed = await restored.snapshot()
        XCTAssertEqual(replayed, snapshot)
    }

    func testLastAffirmedRespiratoryRateWithinOneChunkWins() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("RR 28, RR 22, RR is not 30.")
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot["PATIENT_1"]?.vitals.rr, 22)
    }


    func testQuestionsGoalsAndCoordinatedDenialsAreNotVitals() async {
        for text in ["HR 110?", "Is respiratory rate 22?", "Target: HR 100.",
                     "If bleeding, respiratory rate 22.", "Target respiratory rate 22.",
                     "No measurable heart rate 120 or RR 22.", "No HR 120 and RR 22.",
                     "No respiratory rate 22.", "Patient sat up at 3."] {
            let engine = PatientStateEngine.standard()
            await engine.processTranscript(text)
            let snapshot = await engine.snapshot()
            XCTAssertNil(snapshot["PATIENT_1"]?.vitals.hr, text)
            XCTAssertNil(snapshot["PATIENT_1"]?.vitals.rr, text)
            XCTAssertNil(snapshot["PATIENT_1"]?.vitals.spo2, text)
        }
    }


    func testRateDerivedRespirationStatusFollowsReassessmentAndReplay() async {
        let engine = PatientStateEngine.standard()
        for (rr, status) in [(28, "tachypneic"), (18, "normal"), (8, "bradypneic")] {
            await engine.processTranscript("RR \(rr).")
            let patient = await engine.snapshot()["PATIENT_1"]
            XCTAssertEqual(patient?.vitals.rr, rr)
            XCTAssertEqual(patient?.march.respirationStatus, status)
        }
        let log = await engine.log
        let restored = PatientStateEngine.standard()
        await restored.restore(log)
        let expected = await engine.snapshot()
        let actual = await restored.snapshot()
        XCTAssertEqual(actual, expected)
    }

}
