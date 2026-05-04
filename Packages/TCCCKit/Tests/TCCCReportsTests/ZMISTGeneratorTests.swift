// ZMISTGeneratorTests
//
// Per-patient Z/M/I/S/T block assertions. Covers single patient, multi
// patient, and missing-field paths. Mirrors fixtures from
// /Users/ama/TCCC_FEB_2026/tests/test_reports_validation.py and helper logic
// from /Users/ama/TCCC_FEB_2026/src/reports.py.

import XCTest
@testable import TCCCReports
import TCCCDomain

final class ZMISTGeneratorTests: XCTestCase {

    // -------------------------------------------------------------- helpers

    private func gswPatient(id: String = "PATIENT_1") -> PatientState {
        return PatientState(
            patientId: id,
            mechanismOfInjury: "GSW right thigh",
            march: MARCHState(
                hemorrhageIdentified: true,
                hemorrhageLocation: "right thigh",
                hemorrhageIntervention: "tourniquet R thigh",
                hemorrhageEffective: true,
                airwayStatus: "patent",
                consciousness: "Alert"
            ),
            vitals: Vitals(
                hr: 138,
                bp: BloodPressure(systolic: 80, diastolic: 40, palpated: true),
                spo2: 92,
                rr: 24,
                gcs: 14
            ),
            interventions: [
                Intervention(
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    kind: .tourniquet,
                    description: "TQ R thigh"
                )
            ],
            injuries: ["GSW R upper thigh"],
            classification: .urgent
        )
    }

    // -------------------------------------------------------------- empty

    func testEmptyPatientListReturnsBannerOnly() {
        let report = ZMISTGenerator().generate(from: [])
        XCTAssertEqual(report.kind, .zmist)
        XCTAssertTrue(report.isFallback)
        XCTAssertTrue(report.formattedText.contains(ZMISTGenerator.fallbackBanner))
        XCTAssertTrue(report.formattedText.contains("No patients identified in assessment."))
    }

    // ---------------------------------------------------------- single patient

    func testSinglePatientHasAllFiveZMISTLines() {
        let p = gswPatient()
        let report = ZMISTGenerator().generate(from: [p])
        let text = report.formattedText

        // Banner first
        XCTAssertTrue(text.hasPrefix(ZMISTGenerator.fallbackBanner))

        // Patient block sequence with single-letter prefixes.
        XCTAssertTrue(text.contains("\nPATIENT_1\n"))
        XCTAssertTrue(text.contains("\nZ: PATIENT_1 · Urgent\n"))
        XCTAssertTrue(text.contains("\nM: GSW right thigh\n"))
        // I-line should mention hemorrhage and the typed injury.
        XCTAssertTrue(text.contains("\nI: Hemorrhage: right thigh; GSW R upper thigh\n"))
        // S-line should match exactly the documented format.
        XCTAssertTrue(text.contains("\nS: HR 138 · BP 80/40P · SpO2 92% · RR 24 · GCS 14"))
        // T-line should include the hemorrhage intervention with effectiveness.
        XCTAssertTrue(text.contains("\nT: tourniquet R thigh (effective)"))
    }

    // ---------------------------------------------------------- prefix presence

    func testEveryLineHasItsZMISTPrefix() {
        let p = gswPatient()
        let report = ZMISTGenerator().generate(from: [p])
        let text = report.formattedText
        // Each prefix must appear at start-of-line at least once.
        for prefix in ["Z:", "M:", "I:", "S:", "T:"] {
            XCTAssertTrue(text.contains("\n\(prefix) "), "Missing prefix \(prefix)")
        }
    }

    // ---------------------------------------------------------- multi-patient

    func testTwoPatientBlocksAreSeparated() {
        let p1 = gswPatient(id: "PATIENT_1")
        let p2 = PatientState(
            patientId: "PATIENT_2",
            mechanismOfInjury: "laceration forearm",
            march: MARCHState(
                hemorrhageLocation: "left forearm",
                hemorrhageIntervention: "Pressure dressing",
                consciousness: "Alert"
            ),
            vitals: Vitals(
                hr: 72,
                bp: BloodPressure(systolic: 120, diastolic: 78),
                spo2: 99,
                rr: 16,
                gcs: 15
            ),
            classification: .priority
        )
        let report = ZMISTGenerator().generate(from: [p1, p2])
        let text = report.formattedText

        XCTAssertTrue(text.contains("\nPATIENT_1\n"))
        XCTAssertTrue(text.contains("\nPATIENT_2\n"))
        XCTAssertTrue(text.contains("\nZ: PATIENT_1 · Urgent\n"))
        XCTAssertTrue(text.contains("\nZ: PATIENT_2 · Priority\n"))
        XCTAssertTrue(text.contains("\nT: Pressure dressing"))
        // Blocks separated by a blank line (\n\n).
        XCTAssertTrue(text.contains("\n\nPATIENT_2\n"))
    }

    // ---------------------------------------------------------- missing fields

    func testMissingMechanismFallsBackToUnknown() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Alert"),
            classification: .priority
        )
        let report = ZMISTGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("\nM: UNKNOWN\n"))
    }

    func testMissingClassificationFallsBackToPENDING() {
        let p = PatientState(patientId: "PATIENT_1")
        let report = ZMISTGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("\nZ: PATIENT_1 · PENDING\n"))
    }

    func testMissingInjuriesUsesPlaceholder() {
        let p = PatientState(patientId: "PATIENT_1", classification: .routine)
        let report = ZMISTGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("\nI: see narrative\n"))
    }

    func testMissingTreatmentsUsesPlaceholder() {
        let p = PatientState(patientId: "PATIENT_1", classification: .routine)
        let report = ZMISTGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("\nT: see narrative"))
    }

    func testEmptyVitalsAllPlaceholders() {
        let p = PatientState(patientId: "PATIENT_1", classification: .routine)
        let report = ZMISTGenerator().generate(from: [p])
        let dash = ZMISTGenerator.missingVitalsPlaceholder
        XCTAssertTrue(report.formattedText.contains(
            "\nS: HR \(dash) · BP \(dash) · SpO2 \(dash) · RR \(dash) · GCS \(dash)"
        ))
    }

    // ---------------------------------------------------------- vitals format

    func testNonPalpatedBPDoesNotEmitPSuffix() {
        let p = PatientState(
            patientId: "PATIENT_1",
            vitals: Vitals(
                hr: 80,
                bp: BloodPressure(systolic: 120, diastolic: 80, palpated: false),
                spo2: 98,
                rr: 16,
                gcs: 15
            ),
            classification: .routine
        )
        let report = ZMISTGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("\nS: HR 80 · BP 120/80 · SpO2 98% · RR 16 · GCS 15"))
        XCTAssertFalse(report.formattedText.contains("80/80P"))
    }

    func testPalpatedBPEmitsPSuffix() {
        let p = PatientState(
            patientId: "PATIENT_1",
            vitals: Vitals(
                bp: BloodPressure(systolic: 70, diastolic: 0, palpated: true)
            ),
            classification: .urgent
        )
        let report = ZMISTGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("BP 70/0P"))
    }

    // ---------------------------------------------------------- pneumothorax

    func testPneumothoraxAddsPossiblePneumothoraxToInjuries() {
        let p = PatientState(
            patientId: "PATIENT_1",
            mechanismOfInjury: "blast",
            march: MARCHState(
                respirationStatus: "tension pneumothorax",
                respirationIntervention: "Needle decompression",
                consciousness: "Voice"
            ),
            classification: .urgentSurgical
        )
        let report = ZMISTGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("Possible pneumothorax"))
        XCTAssertTrue(report.formattedText.contains("Needle decompression"))
    }

    // ---------------------------------------------------------- t-line ordering

    func testTLineOrdersHemorrhageThenAirwayThenRespiration() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(
                hemorrhageIntervention: "TQ left thigh",
                hemorrhageEffective: true,
                airwayIntervention: "NPA inserted",
                respirationIntervention: "Chest seal applied",
                circulationIntervention: "IV access established",
                hypothermiaPrevention: "Hypothermia wrap"
            ),
            classification: .urgent
        )
        let report = ZMISTGenerator().generate(from: [p])
        let text = report.formattedText

        // The T-line text from "T: " to the next \n should preserve order.
        // Pull out the substring after "T: ".
        guard let range = text.range(of: "\nT: ") else {
            XCTFail("Missing T-line"); return
        }
        let after = text[range.upperBound...]
        let endIdx = after.firstIndex(of: "\n") ?? after.endIndex
        let tLine = String(after[..<endIdx])
        let parts = tLine.components(separatedBy: "; ")
        XCTAssertEqual(parts[0], "TQ left thigh (effective)")
        XCTAssertEqual(parts[1], "NPA inserted")
        XCTAssertEqual(parts[2], "Chest seal applied")
        XCTAssertEqual(parts[3], "IV access established")
        XCTAssertEqual(parts[4], "Hypothermia wrap")
    }

    // ---------------------------------------------------------- paws fields

    func testTLineIncludesPAWSInterventions() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Alert"),
            classification: .priority,
            paws: PAWSAssessment(
                pain: "Combat pill pack administered",
                antibiotics: "Moxifloxacin administered",
                wounds: "Wound care performed",
                splinting: "SAM splint"
            )
        )
        let report = ZMISTGenerator().generate(from: [p])
        let text = report.formattedText
        XCTAssertTrue(text.contains("SAM splint"))
        XCTAssertTrue(text.contains("Combat pill pack administered"))
        XCTAssertTrue(text.contains("Moxifloxacin administered"))
        XCTAssertTrue(text.contains("Wound care performed"))
    }

    // ---------------------------------------------------------- intervention dedup

    func testTourniquetInterventionDoesNotDuplicateHemorrhageEntry() {
        // Hemorrhage already records "tourniquet R thigh"; the typed
        // Intervention entry of kind .tourniquet must not double-print.
        let p = gswPatient()
        let report = ZMISTGenerator().generate(from: [p])
        let text = report.formattedText
        // Find T-line, count tourniquet occurrences.
        let tourniquetCount = text.components(separatedBy: "tourniquet").count - 1
        XCTAssertEqual(tourniquetCount, 1, "Tourniquet description should appear exactly once")
    }

    // ---------------------------------------------------------- metadata

    func testReportKindAndFallbackFlag() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let report = ZMISTGenerator().generate(from: [gswPatient()], at: when)
        XCTAssertEqual(report.kind, .zmist)
        XCTAssertTrue(report.isFallback)
        XCTAssertEqual(report.generatedAt, when)
    }
}
