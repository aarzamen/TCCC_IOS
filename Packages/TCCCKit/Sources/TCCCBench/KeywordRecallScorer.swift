import Foundation

public struct KeywordRecall: Sendable, Codable, Equatable {
    public let hits: [String]
    public let misses: [String]
    public var recall: Double {
        let total = hits.count + misses.count
        return total == 0 ? 0.0 : Double(hits.count) / Double(total)
    }

    public init(hits: [String], misses: [String]) {
        self.hits = hits
        self.misses = misses
    }
}

/// Secondary metric (the fixture keyword list is fixture-overfitted — see
/// spec §4.1). A keyword matches when its normalized tokens appear as a
/// contiguous subsequence of the normalized transcript tokens.
public enum KeywordRecallScorer {
    public static func score(
        keywords: [String],
        transcriptTokens: [String],
        extraFolds: [[String]] = []
    ) -> KeywordRecall {
        var hits: [String] = []
        var misses: [String] = []
        for keyword in keywords {
            let needle = TokenNormalizer.tokens(keyword, extraFolds: extraFolds)
            if needle.isEmpty { continue }
            if containsSubsequence(haystack: transcriptTokens, needle: needle) {
                hits.append(keyword)
            } else {
                misses.append(keyword)
            }
        }
        return KeywordRecall(hits: hits, misses: misses)
    }

    private static func containsSubsequence(haystack: [String], needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }
}
