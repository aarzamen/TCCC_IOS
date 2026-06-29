import XCTest
import TCCCDomain
import TCCCReports
@testable import TCCC_IOS

@MainActor
final class DD1380WiringTests: XCTestCase {

    // The Handoff card's `isReady` and `shareDD1380PDF` both gate on a casualty
    // existing — makeDD1380Card mirrors that exactly.
    func testMakeCardNilWithoutPatient() {
        let s = AppState()
        XCTAssertNil(s.primaryPatient)
        XCTAssertNil(s.makeDD1380Card(), "No casualty state → no card (card disabled).")
    }

    func testMakeCardNonNilWithPatientCarriesAppMetadata() {
        let s = AppState()
        s.primaryPatient = PatientState(
            patientId: "PATIENT_1",
            mechanismOfInjury: "GSW",
            march: MARCHState(hemorrhageLocation: "right thigh"),
            classification: .urgent
        )

        let card = try? XCTUnwrap(s.makeDD1380Card())
        XCTAssertNotNil(card)
        // App-state identity flows through deterministically (mock values).
        XCTAssertEqual(card?.nameLastFirst, s.casualtyName)          // "DOE, J."
        XCTAssertEqual(card?.unit, s.casualtyUnit)                   // "2/75 RGR"
        XCTAssertEqual(card?.allergies, s.casualtyAllergies)         // "NKDA"
        XCTAssertEqual(card?.last4, "4471")                          // from "••• 4471"
        XCTAssertEqual(card?.battleRosterNumber, "JD4471")          // derived
        // Clinical mapping is present.
        XCTAssertEqual(card?.evacCategory, .urgent)
        XCTAssertTrue(card?.mechanisms.gsw == true)
    }

    // Masked-service-number → last-4 extraction.
    func testLast4DigitsExtraction() {
        XCTAssertEqual(AppState.last4Digits(from: "••• 4471"), "4471")
        XCTAssertEqual(AppState.last4Digits(from: "123456789"), "6789")
        XCTAssertEqual(AppState.last4Digits(from: "12"), "")        // <4 digits → blank
        XCTAssertEqual(AppState.last4Digits(from: ""), "")
    }

    // End-to-end seam: a mapped card renders + exports to a protected PDF.
    func testMakeCardRendersAndExports() async throws {
        let s = AppState()
        s.primaryPatient = PatientState(patientId: "PATIENT_1", classification: .priority)
        let card = try XCTUnwrap(s.makeDD1380Card())

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tccc-wire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = try await DD1380PDFExportService().export(
            card: card, casualtyId: s.casualtyId, documentsURL: tmp)
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
