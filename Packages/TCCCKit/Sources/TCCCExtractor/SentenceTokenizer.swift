// SentenceTokenizer
//
// Faithful Swift port of the inline sentence-tokenisation step from
// `_normalise_spoken_numbers`'s call site in
// /Users/ama/TCCC_FEB_2026/src/state.py around line 500:
//
//     sentences = re.split(r"(?<=[.!?])\s+|\n+", text)
//     sentences = [s.strip() for s in sentences if s.strip()]
//
// We deliberately avoid `NSLinguisticTagger` and `NLTokenizer` because they
// diverge from Python's regex behaviour for medical abbreviations
// ("Sgt.", "Dr.", "Lt."), numeric decimals ("3.5cm"), and run-on sentences.
// Mirroring the regex directly preserves the engine's documented routing
// semantics across the scenario fixtures and the Python regression suite.
//
// Foundation only.

import Foundation

/// Splits raw transcript text into sentences using the same regex Python uses
/// in `state.py:process_transcript`. Empty/whitespace-only fragments are
/// dropped, matching the Python list-comprehension filter.
public struct SentenceTokenizer: Sendable {

    /// Lookbehind regex: split on whitespace that follows a sentence-ending
    /// punctuation mark, OR on one-or-more newlines. Identical alternation to
    /// Python's `re.split(r"(?<=[.!?])\s+|\n+", text)`.
    private let splitter: NSRegularExpression

    public init() {
        // (?<=[.!?])\s+   - whitespace AFTER a sentence-end punctuation
        // |               - OR
        // \n+             - one or more newlines
        let pattern = "(?<=[.!?])\\s+|\\n+"
        self.splitter = try! NSRegularExpression(pattern: pattern, options: [])
    }

    /// Tokenize `text` into sentences. Returns trimmed, non-empty sentences in
    /// reading order.
    public func tokenize(_ text: String) -> [String] {
        if text.isEmpty { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = splitter.matches(in: text, options: [], range: fullRange)

        var pieces: [String] = []
        var cursor = 0

        for match in matches {
            let r = match.range
            // Slice from cursor up to the start of the split match.
            if r.location > cursor {
                let slice = nsText.substring(
                    with: NSRange(location: cursor, length: r.location - cursor))
                pieces.append(slice)
            } else {
                // Splits at the very beginning produce an empty leading piece.
                pieces.append("")
            }
            cursor = r.location + r.length
        }

        // Trailing piece after the final split.
        if cursor < nsText.length {
            let slice = nsText.substring(
                with: NSRange(location: cursor, length: nsText.length - cursor))
            pieces.append(slice)
        }

        // Mirror Python: `[s.strip() for s in sentences if s.strip()]`
        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
