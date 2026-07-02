import Foundation

public struct WERResult: Sendable, Codable, Equatable {
    public let substitutions: Int
    public let insertions: Int
    public let deletions: Int
    public let referenceCount: Int

    public var errorCount: Int { substitutions + insertions + deletions }
    /// Convention: empty reference + non-empty hypothesis = 1.0.
    public var wer: Double {
        if referenceCount == 0 { return errorCount == 0 ? 0.0 : 1.0 }
        return Double(errorCount) / Double(referenceCount)
    }

    public init(substitutions: Int, insertions: Int, deletions: Int, referenceCount: Int) {
        self.substitutions = substitutions
        self.insertions = insertions
        self.deletions = deletions
        self.referenceCount = referenceCount
    }
}

/// Classic Levenshtein alignment with backtrace so S/I/D are reported
/// separately (WER = (S+I+D)/N over the reference).
public enum WERScorer {
    public static func score(reference: [String], hypothesis: [String]) -> WERResult {
        let n = reference.count, m = hypothesis.count
        // dp[i][j] = edit distance between ref[0..<i] and hyp[0..<j]
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let subCost = reference[i - 1] == hypothesis[j - 1] ? 0 : 1
                    dp[i][j] = min(
                        dp[i - 1][j - 1] + subCost, // match/substitute
                        dp[i - 1][j] + 1,           // deletion (ref word dropped)
                        dp[i][j - 1] + 1            // insertion (extra hyp word)
                    )
                }
            }
        }
        // Backtrace.
        var s = 0, ins = 0, del = 0
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0,
               dp[i][j] == dp[i - 1][j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1) {
                if reference[i - 1] != hypothesis[j - 1] { s += 1 }
                i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                del += 1; i -= 1
            } else {
                ins += 1; j -= 1
            }
        }
        return WERResult(substitutions: s, insertions: ins, deletions: del, referenceCount: n)
    }
}
