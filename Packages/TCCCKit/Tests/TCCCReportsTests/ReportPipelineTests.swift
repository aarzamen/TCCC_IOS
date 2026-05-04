// ReportPipelineTests
//
// Smoke tests for the dual-emit convenience layer.

import XCTest
@testable import TCCCReports
import TCCCDomain

final class ReportPipelineTests: XCTestCase {

    private func samplePatient() -> PatientState {
        return PatientState(
            patientId: "PATIENT_1",
            mechanismOfInjury: "GSW right thigh",
            march: MARCHState(
                hemorrhageIdentified: true,
                hemorrhageLocation: "right thigh",
                hemorrhageIntervention: "tourniquet R thigh",
                hemorrhageEffective: true,
                consciousness: "Alert"
            ),
            vitals: Vitals(hr: 110, spo2: 96),
            classification: .urgent
        )
    }

    func testReturnsTwoReportsInOrderNineLineThenZMIST() {
        let pipeline = ReportPipeline()
        let reports = pipeline.generateAll(from: [samplePatient()])
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].kind, .nineLine)
        XCTAssertEqual(reports[1].kind, .zmist)
    }

    func testEachReportIsMarkedFallback() {
        let reports = ReportPipeline().generateAll(from: [samplePatient()])
        XCTAssertTrue(reports.allSatisfy { $0.isFallback })
    }

    func testTimestampPropagatesIntoBothReports() {
        let when = Date(timeIntervalSince1970: 1_715_000_000)
        let reports = ReportPipeline().generateAll(from: [samplePatient()], at: when)
        XCTAssertEqual(reports[0].generatedAt, when)
        XCTAssertEqual(reports[1].generatedAt, when)
    }

    func testEmptyPatientListStillReturnsTwoBannerOnlyReports() {
        let reports = ReportPipeline().generateAll(from: [])
        XCTAssertEqual(reports.count, 2)
        XCTAssertTrue(reports[0].formattedText.contains("No patients identified"))
        XCTAssertTrue(reports[1].formattedText.contains("No patients identified"))
    }

    func testCustomMedevacGeneratorParamsPropagate() {
        let medevac = MedevacGenerator(
            callsign: "CHARLIE 1",
            frequency: "44.10 FM",
            location: "MGRS 38S MB 1234 5678"
        )
        let pipeline = ReportPipeline(medevac: medevac)
        let reports = pipeline.generateAll(from: [samplePatient()])
        XCTAssertTrue(reports[0].formattedText.contains("\nLINE 1: MGRS 38S MB 1234 5678"))
        XCTAssertTrue(reports[0].formattedText.contains("\nLINE 2: 44.10 FM · CHARLIE 1"))
    }

    func testReportCodableRoundTrip() throws {
        let when = Date(timeIntervalSince1970: 1_715_000_000)
        let reports = ReportPipeline().generateAll(from: [samplePatient()], at: when)
        for r in reports {
            let data = try JSONEncoder().encode(r)
            let decoded = try JSONDecoder().decode(Report.self, from: data)
            XCTAssertEqual(decoded, r)
        }
    }
}
