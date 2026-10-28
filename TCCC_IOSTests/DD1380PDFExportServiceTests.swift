import XCTest
import CoreGraphics
import PDFKit
import TCCCReports
@testable import TCCC_IOS

final class DD1380PDFExportServiceTests: XCTestCase {

    private func temporaryDirectory() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tccc-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return tmp
    }

    private func card() -> DD1380CardData {
        var card = DD1380CardData()
        card.nameLastFirst = "DOE, J."
        card.evacCategory = .urgent
        return card
    }

    func testExportWritesProtectedPDFFile() async throws {
        let tmp = try temporaryDirectory()
        let service = DD1380PDFExportService()
        let url = try await service.export(card: card(), casualtyId: "C-04", documentsURL: tmp).url

        // .pdf extension + deterministic, safe filename.
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("DD1380_C-04_"))

        // File exists and is non-empty valid PDF.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        XCTAssertNotNil(CGPDFDocument(provider))

        // Protected at rest. ProtectedWrite uses .completeFileProtection; the
        // SIMULATOR (no passcode / secure enclave) downgrades that to
        // .completeUntilFirstUserAuthentication when read back. On a real device
        // it is .complete. Accept either complete-class protection — never .none.
        if let prot = try? url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection {
            XCTAssertTrue(prot == .complete || prot == .completeUntilFirstUserAuthentication,
                          "Expected complete-class protection, got \(prot)")
        }
    }

    func testExportUsesOfficialForm() async throws {
        let result = try await DD1380PDFExportService()
            .export(card: card(), casualtyId: "C-04", documentsURL: try temporaryDirectory())
        XCTAssertTrue(result.usedOfficialForm)
        let doc = try XCTUnwrap(PDFDocument(url: result.url))
        XCTAssertTrue(doc.page(at: 0)?.string?.contains(DD1380OfficialForm.edition) == true)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("DOE, J.") == true)
    }

    func testExportFallsBackWhenTemplateMissing() async throws {
        let service = DD1380PDFExportService(bundle: Bundle(for: Self.self))   // test bundle has no template
        let result = try await service.export(card: card(), casualtyId: "C-04", documentsURL: try temporaryDirectory())
        XCTAssertFalse(result.usedOfficialForm)
        let doc = try XCTUnwrap(PDFDocument(url: result.url))
        XCTAssertEqual(doc.pageCount, 2)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("DOE, J.") == true)
    }
}
