import Foundation
import TCCCReports

/// Renders a `DD1380CardData` to a protected PDF on disk and returns its URL.
/// The file is CUI when filled — written with `NSFileProtectionComplete` via
/// `ProtectedWrite`, never auto-shared or transmitted. The caller (Handoff)
/// hands the URL to the iOS share sheet only on explicit operator action.
actor DD1380PDFExportService {

    func export(card: DD1380CardData, casualtyId: String, documentsURL: URL) async throws -> URL {
        let data = try DD1380PDFRenderer.render(card)
        let stamp = Self.stampFormatter.string(from: Date())
        let url = documentsURL.appendingPathComponent("DD1380_\(Self.sanitize(casualtyId))_\(stamp).pdf")
        try ProtectedWrite.data(data, to: url)
        return url
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
