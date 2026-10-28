import Foundation
import TCCCReports

/// Where an exported DD 1380 was written, and whether it is the official form.
struct DD1380ExportResult: Sendable {
    let url: URL
    /// False only when the bundled official template could not be used and the
    /// vector fallback layout was written instead.
    let usedOfficialForm: Bool
}

/// Renders a `DD1380CardData` to a protected PDF on disk and returns its URL.
/// The official DD Form 1380 (JUN 2014) is filled and flattened; the vector
/// fallback layout is used only if the bundled template is missing or
/// unreadable, so an export never fails for that reason. The file is CUI when
/// filled — written with `NSFileProtectionComplete` via `ProtectedWrite`, never
/// auto-shared or transmitted. The caller (Handoff) hands the URL to the iOS
/// share sheet only on explicit operator action.
actor DD1380PDFExportService {

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func export(card: DD1380CardData, casualtyId: String, documentsURL: URL) async throws -> DD1380ExportResult {
        let data: Data
        let official: Bool
        do {
            data = try DD1380OfficialFormFiller.render(card, bundle: bundle)
            official = true
        } catch is DD1380FillError {
            data = try DD1380PDFRenderer.render(card)
            official = false
        }
        let stamp = Self.stampFormatter.string(from: Date())
        let url = documentsURL.appendingPathComponent("DD1380_\(Self.sanitize(casualtyId))_\(stamp).pdf")
        try ProtectedWrite.data(data, to: url)
        return DD1380ExportResult(url: url, usedOfficialForm: official)
    }

    /// Deterministic, filesystem-safe casualty id (alphanumerics → kept, all
    /// else → "-"), so a value like "C-04" or "PATIENT/1" yields a clean name.
    private static func sanitize(_ id: String) -> String {
        let mapped = id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped)
        return collapsed.isEmpty ? "casualty" : collapsed
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
