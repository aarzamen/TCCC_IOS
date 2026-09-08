import PDFKit
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
        // Explicitly supplied identity (synthetic — set by this test, never
        // relying on AppState defaults) flows through verbatim.
        s.casualtyName = "SMITH, A."
        s.casualtyUnit = "1/1 TEST BN"
        s.casualtyServiceNumberMasked = "••• 1234"
        s.casualtyAllergies = "PENICILLIN"
        s.primaryPatient = PatientState(
            patientId: "PATIENT_1",
            mechanismOfInjury: "GSW",
            march: MARCHState(hemorrhageLocation: "right thigh"),
            classification: .urgent
        )

        let card = try? XCTUnwrap(s.makeDD1380Card())
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.nameLastFirst, "SMITH, A.")
        XCTAssertEqual(card?.unit, "1/1 TEST BN")
        XCTAssertEqual(card?.allergies, "PENICILLIN")
        XCTAssertEqual(card?.last4, "1234")
        XCTAssertEqual(card?.battleRosterNumber, "AS1234")          // derived from explicit values
        // Clinical mapping is present.
        XCTAssertEqual(card?.evacCategory, .urgent)
        XCTAssertTrue(card?.mechanisms.gsw == true)
    }

    // MARK: - Truthful-defaults contract (2026-09-07 capture-reliability sprint)

    // A fresh real encounter has no roster/intake source, so every §A identity
    // field and the §H first-responder identity must map blank — no invented
    // casualty, no fabricated "NKDA".
    func testFreshCasualtyMapsBlankIdentity() throws {
        let s = AppState()
        s.primaryPatient = PatientState(patientId: "PATIENT_1", classification: .priority)
        let card = try XCTUnwrap(s.makeDD1380Card())

        XCTAssertEqual(card.nameLastFirst, "", "Unknown casualty name must map blank, not a mock.")
        XCTAssertEqual(card.unit, "", "Unknown unit must map blank.")
        XCTAssertEqual(card.last4, "", "Unknown service number must yield a blank last-4.")
        XCTAssertEqual(card.battleRosterNumber, "", "No name/last-4 → no derivable battle roster #.")
        XCTAssertEqual(card.allergies, "", "Unknown allergies must NOT default to NKDA.")
        XCTAssertEqual(card.firstResponderName, "", "No operator entry → no fabricated first responder.")
        XCTAssertEqual(card.firstResponderLast4, "")
    }

    // Explicit NKDA remains valid — blank-by-default must not forbid the
    // operator asserting "no known drug allergies".
    func testExplicitNKDAIsPreserved() throws {
        let s = AppState()
        s.casualtyAllergies = "NKDA"
        s.primaryPatient = PatientState(patientId: "PATIENT_1", classification: .routine)
        let card = try XCTUnwrap(s.makeDD1380Card())
        XCTAssertEqual(card.allergies, "NKDA")
    }

    // The rendered PDF for a fresh encounter must not contain any of the
    // historical mock header literals. Inspects actual PDF text via PDFKit.
    func testFreshCasualtyPDFContainsNoFabricatedHeaderValues() throws {
        let s = AppState()
        s.primaryPatient = PatientState(patientId: "PATIENT_1", classification: .priority)
        let card = try XCTUnwrap(s.makeDD1380Card())
        let data = try DD1380PDFRenderer.render(card)
        let doc = try XCTUnwrap(PDFDocument(data: data))
        var text = ""
        for i in 0..<doc.pageCount { text += doc.page(at: i)?.string ?? "" }
        XCTAssertFalse(text.isEmpty, "PDF should carry extractable text for inspection.")

        for fabricated in ["DOE", "2/75", "RGR", "4471", "JD4471", "NKDA"] {
            XCTAssertFalse(text.contains(fabricated),
                           "Fresh-encounter PDF must not contain fabricated default '\(fabricated)'.")
        }
    }

    // MARK: - Lifecycle identity reset
    //
    // These run with `encounterStore == nil` (AppState.load() never called), so
    // newPatient()/wipeSession() skip all disk work (`persistNewEvents` guards on
    // the store; the purge/archive branches are store-gated) — no persistent
    // Documents paths, microphone, or model are touched.

    // NEW CASUALTY must not carry the prior casualty's explicit identity forward.
    func testNewPatientClearsCasualtyIdentity() async throws {
        let s = AppState()
        s.casualtyName = "SMITH, A."
        s.casualtyUnit = "1/1 TEST BN"
        s.casualtyServiceNumberMasked = "••• 1234"
        s.casualtyAllergies = "PENICILLIN"

        await s.newPatient()

        XCTAssertEqual(s.casualtyName, "", "Identity is encounter-scoped; NEW CASUALTY must clear it.")
        XCTAssertEqual(s.casualtyUnit, "")
        XCTAssertEqual(s.casualtyServiceNumberMasked, "")
        XCTAssertEqual(s.casualtyAllergies, "")
    }

    // WIPE re-arms a fresh casualty; identity must be blank, not the mock defaults.
    func testWipeSessionClearsCasualtyIdentity() async throws {
        let s = AppState()
        s.casualtyName = "SMITH, A."
        s.casualtyUnit = "1/1 TEST BN"
        s.casualtyServiceNumberMasked = "••• 1234"
        s.casualtyAllergies = "PENICILLIN"

        await s.wipeSession()

        XCTAssertEqual(s.casualtyName, "")
        XCTAssertEqual(s.casualtyUnit, "")
        XCTAssertEqual(s.casualtyServiceNumberMasked, "")
        XCTAssertEqual(s.casualtyAllergies, "")
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
