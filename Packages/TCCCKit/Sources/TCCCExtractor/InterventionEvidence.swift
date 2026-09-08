import Foundation

/// Conservative clause boundaries for the newly supported narrated actions.
/// This does not reinterpret clinical words or change global negation rules.
enum InterventionEvidence {
    private static let speculative = try! NSRegularExpression(
        pattern: #"\b(?:if|unless|plan(?:ned|ning)?|consider(?:ed|ing)?|discuss(?:ed|ing)?|will|would|could|should|may|might|need(?:s|ed)?|recommend(?:ed)?|possible|perhaps|maybe)\b|\b(?:going\s+to|instead\s+of)\b"#,
        options: [.caseInsensitive])
    private static let split = try! NSRegularExpression(pattern: #"[,;\n]|\b(?:but|however)\b"#, options: [.caseInsensitive])
    private static let contractions = try! NSRegularExpression(
        pattern: #"\b(?:never|cannot|can't|didn't|hasn't|haven't|wasn't|weren't|don't|doesn't)\b"#,
        options: [.caseInsensitive])

    static func affirmedClauses(in text: String) -> [String] {
        let text = text.replacingOccurrences(of: "’", with: "'")
        let range = NSRange(text.startIndex..., in: text)
        // A conditional before a comma still governs the proposed action after it.
        guard !text.contains("?"), speculative.firstMatch(in: text, range: range) == nil else { return [] }
        let separated = split.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
        return separated.components(separatedBy: "\n").filter { clause in
            !NegationDetector().sentenceHasNegationMarker(clause)
                && contractions.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)) == nil
        }
    }
}
