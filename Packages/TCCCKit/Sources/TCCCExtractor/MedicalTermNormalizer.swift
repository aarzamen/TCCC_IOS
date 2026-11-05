// MedicalTermNormalizer
//
// Deterministic repair of speech-recognition errors on medical terms. Runs on
// a transcript chunk before spoken-number normalization and sentence
// tokenization (see `PatientStateEngine.processTranscript`). Only the
// extraction input changes: the words the recognizer produced stay in the
// `asrSegment` event and on screen, so every correction is auditable against
// the original text.
//
// Every rule is a misheard form observed in a real recording, never a guess
// at what a recognizer might do. First source: the 2026-10-27 iPhone 17 Pro
// recording with Apple Speech (`LiveRecordingRegressionTests`):
//
//   "Is it true rate 16 his SPO2 is 96%"   -> "respiratory rate 16 his SPO2 is 96%"
//   "give him her pen For the antibiotic"  -> "give him ertapenem For the antibiotic"
//   "I gave him a pen him."                -> "I gave him ertapenem."
//
// A rule may require a context cue in the same sentence. "her pen" is only
// ertapenem next to words of giving a drug; "she handed me her pen" is left
// alone. Add a rule only with the recording or benchmark fixture that produced
// the error, and add that sentence to `MedicalTermNormalizerTests`.
//
// Foundation only.

import Foundation

public struct MedicalTermNormalizer: Sendable {

    /// One observed error. `context`, when present, must match somewhere in
    /// the sentence that contains the misheard words.
    struct Rule: Sendable {
        let heard: NSRegularExpression
        let meant: String
        let context: NSRegularExpression?
    }

    private let rules: [Rule]

    /// Sentence boundaries for the context check: the punctuation the tokenizer
    /// splits on, so a cue in the next sentence does not count.
    private static let boundary = CharacterSet(charactersIn: ".!?\n")

    public init() {
        func regex(_ pattern: String) -> NSRegularExpression {
            // Static literals validated by the test suite; a failure is a programmer error.
            try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        // Words that make "her pen" / "a pen" a drug rather than a pen.
        let giving = regex(
            #"\b(?:antibiotics?|gave|give|giving|given|push(?:ed|ing)?|administer(?:ed|ing)?|grams?|mg|iv|im)\b"#)
        self.rules = [
            Rule(heard: regex(#"\bis it true rate\b"#), meant: "respiratory rate", context: nil),
            Rule(heard: regex(#"\b(?:her|a) pen(?: him)?\b"#), meant: "ertapenem", context: giving),
        ]
    }

    /// Rewrite every observed error in `text`; everything else is untouched.
    public func normalize(_ text: String) -> String {
        var result = text
        for rule in rules {
            let ns = result as NSString
            let matches = rule.heard.matches(
                in: result, options: [], range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var rewritten = result
            // Reverse order keeps the earlier match ranges valid while splicing.
            for match in matches.reversed() {
                if let context = rule.context {
                    let sentence = ns.substring(with: Self.sentence(around: match.range, in: ns))
                    let range = NSRange(location: 0, length: (sentence as NSString).length)
                    guard context.firstMatch(in: sentence, options: [], range: range) != nil else { continue }
                }
                rewritten = (rewritten as NSString).replacingCharacters(in: match.range, with: rule.meant)
            }
            result = rewritten
        }
        return result
    }

    /// The sentence containing `range`: from the previous sentence-ending
    /// punctuation (or the start of the text) to the next one (or the end).
    private static func sentence(around range: NSRange, in ns: NSString) -> NSRange {
        let before = ns.rangeOfCharacter(
            from: boundary, options: .backwards, range: NSRange(location: 0, length: range.location))
        let start = before.location == NSNotFound ? 0 : before.location + before.length
        let afterStart = range.location + range.length
        let after = ns.rangeOfCharacter(
            from: boundary, options: [], range: NSRange(location: afterStart, length: ns.length - afterStart))
        let end = after.location == NSNotFound ? ns.length : after.location
        return NSRange(location: start, length: end - start)
    }
}
