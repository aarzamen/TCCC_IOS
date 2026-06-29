import XCTest
import CoreGraphics
import TCCCReports
@testable import TCCC_IOS

final class DD1380PDFExportServiceTests: XCTestCase {

    func testExportWritesProtectedPDFFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tccc-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var card = DD1380CardData()
        card.nameLastFirst = "DOE, J."
        card.evacCategory = .urgent

        let service = DD1380PDFExportService()
        let url = try await service.export(card: card, casualtyId: "C-04", documentsURL: tmp)

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
}
