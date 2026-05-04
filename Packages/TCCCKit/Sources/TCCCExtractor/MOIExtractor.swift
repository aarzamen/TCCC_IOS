import Foundation
import TCCCDomain

/// Mechanism-of-injury extractor.
///
/// Mirrors `state.py:_extract_moi` (lines 569–577) and the `moi_patterns`
/// list at lines 351–358. Once `mechanismOfInjury` is set on a patient it is
/// not overwritten on subsequent sentences (matches Python guard).
public struct MOIExtractor: ExtractorPass {

    private struct PatternEntry {
        let regex: NSRegularExpression
        let label: String
    }

    private let patterns: [PatternEntry]

    public init() {
        let raw: [(String, String)] = [
            (#"gunshot|gsw|bullet"#, "GSW"),
            (#"\bied\b|ied\s+blast|\bblast\b|\bexplosion\b|\bbomb\b"#, "IED blast"),
            (#"shrapnel|fragment"#, "Shrapnel/fragmentation"),
            (#"stab|knife|laceration"#, "Penetrating trauma"),
            (#"\bfall\b|\bfell\b"#, "Fall"),
            (#"mva|vehicle|crash|collision"#, "MVA"),
        ]
        self.patterns = raw.compactMap { pattern, label in
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return PatternEntry(regex: re, label: label)
        }
    }

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        if state.mechanismOfInjury != nil { return state }
        // Python `_extract_moi` (state.py:569–577) does not gate on negation —
        // it just regex-matches and sets MOI. Mirror this. Negation gating here
        // would cause sentences like "No head injury, he just fell." to miss
        // the Fall MOI because the `no head` prefix flips the sentence flag.
        let sentence = context.sentence
        let range = NSRange(sentence.startIndex..., in: sentence)

        for entry in patterns {
            if entry.regex.firstMatch(in: sentence, options: [], range: range) != nil {
                var newState = state
                newState.mechanismOfInjury = entry.label
                return newState
            }
        }
        return state
    }
}
