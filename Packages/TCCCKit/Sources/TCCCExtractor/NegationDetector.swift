// NegationDetector
//
// Faithful Swift port of `has_negated_finding` and the `NEGATION_PREFIXES`
// table from /Users/ama/TCCC_FEB_2026/src/state.py (lines 11–35).
//
// The Python implementation:
//
//     NEGATION_PREFIXES = [
//         r"no signs? of",
//         r"negative for",
//         r"denies",
//         r"without",
//         r"no evidence of",
//         r"absent",
//         r"\bno\b",
//         r"\bnothing\b",
//         r"\bnot\b",
//     ]
//
//     def has_negated_finding(text, finding, window=5):
//         finding_re = re.escape(finding.lower())
//         for neg in NEGATION_PREFIXES:
//             pattern = rf"{neg}\s+(?:\w+\s+){{0,{window}}}{finding_re}"
//             if re.search(pattern, text.lower()):
//                 return True
//         return False
//
// We mirror the prefix order (more specific first, bare "no" last) and the
// 5-word default window. `NSRegularExpression` matches Python `re` semantics
// closely enough for these patterns (no lookbehinds, simple word boundaries).
//
// Foundation only.

import Foundation

/// Detects clinical negation patterns ("no signs of pneumothorax",
/// "denies chest pain", etc.) in a sentence. Run before any positive-finding
/// extraction.
public struct NegationDetector: Sendable {

    /// Negation prefix regex fragments, in priority order. Order matters: the
    /// more specific multi-word prefixes appear before the catch-all bare-word
    /// ones, so positive matches by the specific patterns are preferred when
    /// the same sentence triggers multiple.
    private static let negationPrefixes: [String] = [
        "no signs? of",
        "negative for",
        "denies",
        "without",
        "no evidence of",
        "absent",
        "\\bno\\b",
        "\\bnothing\\b",
        "\\bnot\\b",
    ]

    /// Default word window between negation prefix and finding. Matches the
    /// Python `window: int = 5` default.
    public static let defaultWindow: Int = 5

    public init() {}

    /// Returns true if `finding` appears under a negation marker within
    /// `window` words. Direct port of `has_negated_finding(text, finding, window)`.
    public func hasNegatedFinding(
        in text: String,
        finding: String,
        window: Int = NegationDetector.defaultWindow
    ) -> Bool {
        let lowerText = text.lowercased()
        let escapedFinding = NSRegularExpression.escapedPattern(
            for: finding.lowercased())
        let nsLower = lowerText as NSString
        let fullRange = NSRange(location: 0, length: nsLower.length)

        for neg in Self.negationPrefixes {
            // rf"{neg}\s+(?:\w+\s+){{0,{window}}}{finding_re}"
            let pattern = "\(neg)\\s+(?:\\w+\\s+){0,\(window)}\(escapedFinding)"
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: []) else { continue }
            if regex.firstMatch(in: lowerText, options: [], range: fullRange) != nil {
                return true
            }
        }
        return false
    }

    /// Convenience: detects whether the sentence contains *any* negation
    /// marker at all. Used by the engine's per-sentence loop to set the
    /// `ExtractionContext.isNegated` flag.
    ///
    /// This is a "looser" check than `hasNegatedFinding` — it returns true if
    /// any of the negation prefixes appear anywhere in the sentence, without
    /// requiring a specific finding to follow within the word window.
    public func sentenceHasNegationMarker(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        let nsLower = lowerText as NSString
        let fullRange = NSRange(location: 0, length: nsLower.length)
        for neg in Self.negationPrefixes {
            guard let regex = try? NSRegularExpression(
                pattern: neg, options: []) else { continue }
            if regex.firstMatch(in: lowerText, options: [], range: fullRange) != nil {
                return true
            }
        }
        return false
    }
}
