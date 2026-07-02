import Foundation
import TCCCBench

/// Loads the bundled reference transcript + scoring sidecar for a fixture.
/// Slug rule: fixture file name, lowercased, spaces → underscores, extension
/// dropped ("Valdez Alley.m4a" → "valdez_alley").
struct BenchmarkSidecar: Codable {
    var keywords: [String] = []
    var keywordCaveat: String?
    var knownDefects: [String] = []
    var extraFolds: [[String]] = []
    var fieldExpectations: [FieldExpectation] = []
}

enum BenchmarkReference {
    static func slug(forFixture url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    static func load(slug: String) -> (referenceText: String, sidecar: BenchmarkSidecar)? {
        guard let txtURL = Bundle.main.url(forResource: slug, withExtension: "txt"),
              let text = try? String(contentsOf: txtURL, encoding: .utf8) else { return nil }
        var sidecar = BenchmarkSidecar()
        if let jsonURL = Bundle.main.url(forResource: slug, withExtension: "json"),
           let data = try? Data(contentsOf: jsonURL),
           let decoded = try? JSONDecoder().decode(BenchmarkSidecar.self, from: data) {
            sidecar = decoded
        }
        return (text, sidecar)
    }
}
