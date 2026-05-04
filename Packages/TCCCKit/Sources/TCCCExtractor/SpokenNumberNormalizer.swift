// SpokenNumberNormalizer
//
// Faithful Swift port of `_normalise_spoken_numbers` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 98–233).
//
// Converts spoken-form vital-sign numbers in TCCC transcripts into digit form
// so downstream regex extractors can use simple numeric patterns.
//
// Supported transformations (mirroring the Python source verbatim):
//
//   - "heart rate one ten"                        -> "heart rate 110"
//   - "heart rate one hundred and five"           -> "heart rate 105"
//   - "heart rate ninety-six"                     -> "heart rate 96"
//   - "blood pressure ninety over sixty"          -> "blood pressure 90/60"
//   - "blood pressure one twenty over seventy-eight" -> "blood pressure 120/78"
//   - "pulse ox ninety-six percent"               -> "pulse ox 96%"
//   - "pulse ox ninety-nine"                      -> "pulse ox 99%"
//   - "respiratory rate eighteen"                 -> "respiratory rate 18"
//   - "respiratory rate looks about eighteen"     -> "respiratory rate looks about 18"
//
// Anything outside these specific vital-sign contexts is left untouched
// (e.g. "five minutes ago", "GCS fifteen", "twenty meters", "eighteen gauge").
//
// Foundation only — no SwiftUI, UIKit, Combine, or external deps.

import Foundation

public struct SpokenNumberNormalizer: Sendable {

    // MARK: - Word tables

    /// Single-digit number words. "zero" is included for completeness; note that
    /// `_spoken_to_int("zero")` returns nil because the Python implementation
    /// rejects totals <= 0. We mirror that quirk.
    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]

    /// Teens + multiples-of-ten through ninety.
    private static let tens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    // MARK: - Compiled regex passes
    //
    // Python uses re.sub with an inline lambda. We use NSRegularExpression
    // because its semantics (case-insensitive flag, group capture, backslash
    // escapes) match Python's `re` module closely enough that we can lift the
    // patterns over verbatim. They are compiled lazily once per instance.

    private let hrRegex: NSRegularExpression
    private let bpRegex: NSRegularExpression
    private let spo2Regex: NSRegularExpression
    private let rrRegex: NSRegularExpression

    public init() {
        // Reusable spoken-number alternation fragments matching the Python code.
        // The Python `_repl_hr` chunk uses a slightly different second-group
        // structure than the BP/SpO2/RR ones — preserve the asymmetry exactly.

        // First-token alternation for HR/BP/SpO2/RR group 2 (must match an actual digit word):
        // (?:one\s+hundred(?:\s+and\s+)?|two\s+hundred(?:\s+and\s+)?)?<tens|teen|ones>
        let firstWord =
            "(?:one\\s+hundred(?:\\s+and\\s+)?|two\\s+hundred(?:\\s+and\\s+)?)?" +
            "(?:ninety|eighty|seventy|sixty|fifty|forty|thirty|twenty|ten|" +
            "eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|" +
            "one|two|three|four|five|six|seven|eight|nine)"

        // Continuation tokens (separated by whitespace OR hyphen):
        // (?:[\s\-](?:hundred(?:\s+and\s+)?|<tens|teen|ones|zero>))*
        let cont =
            "(?:[\\s\\-](?:hundred(?:\\s+and\\s+)?|" +
            "ninety|eighty|seventy|sixty|fifty|forty|thirty|twenty|ten|" +
            "eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|" +
            "zero|one|two|three|four|five|six|seven|eight|nine))*"

        // The BP regex uses a slightly narrower first-token alternation
        // (no "two\s+hundred" prefix) — preserve exactly.
        let firstWordBP =
            "(?:one\\s+hundred(?:\\s+and\\s+)?|" +
            "ninety|eighty|seventy|sixty|fifty|forty|thirty|twenty|ten|" +
            "eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|" +
            "one|two|three|four|five|six|seven|eight|nine)"

        // 1) Heart rate:
        //    ((?:heart\s+rate|hr|pulse)\s+(?:is\s+)?(?:of\s+)?)
        //    (<spoken number>)
        let hrPattern =
            "((?:heart\\s+rate|hr|pulse)\\s+(?:is\\s+)?(?:of\\s+)?)" +
            "(" + firstWord + cont + ")"

        // 2) Blood pressure:
        //    ((?:blood\s+pressure|bp)\s+(?:is\s+)?)(<sys>)\s+over\s+(<dia>)
        let bpPattern =
            "((?:blood\\s+pressure|bp)\\s+(?:is\\s+)?)" +
            "(" + firstWordBP + cont + ")" +
            "\\s+over\\s+" +
            "(" + firstWordBP + cont + ")"

        // 3) Pulse-ox / SpO2 / sat (always appends "%"):
        //    ((?:pulse\s+ox|spo2|sat|o2\s+sat)\s+(?:is\s+)?)
        //    (<spoken number>)
        //    (?:\s+percent)?
        let spo2Pattern =
            "((?:pulse\\s+ox|spo2|sat|o2\\s+sat)\\s+(?:is\\s+)?)" +
            "(" + firstWord + cont + ")" +
            "(?:\\s+percent)?"

        // 4) Respiratory rate:
        //    ((?:respiratory\s+rate|rr)\s+(?:is\s+)?(?:looks?\s+(?:about\s+)?)?)
        //    (<spoken number>)
        let rrPattern =
            "((?:respiratory\\s+rate|rr)\\s+(?:is\\s+)?(?:looks?\\s+(?:about\\s+)?)?)" +
            "(" + firstWord + cont + ")"

        // Force-unwraps are safe: these patterns are static literals validated
        // by the test suite. A failure here is a programmer error and should
        // crash hard rather than silently degrade.
        self.hrRegex = try! NSRegularExpression(
            pattern: hrPattern, options: [.caseInsensitive])
        self.bpRegex = try! NSRegularExpression(
            pattern: bpPattern, options: [.caseInsensitive])
        self.spo2Regex = try! NSRegularExpression(
            pattern: spo2Pattern, options: [.caseInsensitive])
        self.rrRegex = try! NSRegularExpression(
            pattern: rrPattern, options: [.caseInsensitive])
    }

    // MARK: - Public API

    /// Replace spoken vital-sign numbers with digits.
    ///
    /// Mirrors `_normalise_spoken_numbers` in `state.py`. Only the four targeted
    /// vital-sign contexts are rewritten; all other text is returned unchanged.
    public func normalize(_ text: String) -> String {
        var result = text
        result = applyHeartRate(to: result)
        result = applyBloodPressure(to: result)
        result = applySpO2(to: result)
        result = applyRespiratoryRate(to: result)
        return result
    }

    // MARK: - Spoken phrase -> Int

    /// Convert a spoken-number phrase to an integer, or nil if not parseable.
    ///
    /// Direct port of Python `_spoken_to_int`. Handles:
    ///   - bare tens/ones:      "eighteen" -> 18, "ninety" -> 90, "five" -> 5
    ///   - tens + ones:         "ninety-six" -> 96, "twenty two" -> 22
    ///   - explicit hundreds:   "one hundred and five" -> 105
    ///   - military shorthand:  "one ten" -> 110, "one twenty" -> 120
    ///
    /// Note: returns nil for "zero" (matching Python's `total > 0` guard).
    static func spokenToInt(_ phrase: String) -> Int? {
        // Lowercase, hyphen->space, then split on whitespace and drop "and"/"a".
        let normalized = phrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")

        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { $0 != "and" && $0 != "a" }

        if tokens.isEmpty { return nil }

        // Special case: military "one <tens>" shorthand
        // ("one ten" -> 110, "one twenty" -> 120, "one thirty" -> 130, ...)
        if tokens.count == 2,
           tokens[0] == "one",
           let tensVal = tens[tokens[1]],
           tensVal >= 10 {
            return 100 + tensVal
        }

        var total = 0
        var current = 0

        for t in tokens {
            if let v = ones[t] {
                current += v
            } else if let v = tens[t] {
                current += v
            } else if t == "hundred" {
                current = current > 0 ? current * 100 : 100
            } else {
                return nil  // unrecognised token
            }
        }

        total += current
        return total > 0 ? total : nil
    }

    // MARK: - Pass implementations
    //
    // Each pass walks matches in reverse so that splice indices stay valid as
    // we mutate the string. NSRegularExpression returns NSRange values relative
    // to the full UTF-16 view of the input.

    private func applyHeartRate(to text: String) -> String {
        return rewrite(text, with: hrRegex) { groups in
            // groups[0] = full match, [1] = prefix (e.g. "heart rate "),
            // [2] = spoken-number words.
            let prefix = groups[1]
            let words = groups[2]

            // Special compounds used in fixtures (preserved verbatim from
            // Python's `_repl_hr`).
            let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
            if matchesIgnoreCase(trimmed, pattern: "^one\\s+ten$") {
                return prefix + "110"
            }
            if matchesIgnoreCase(trimmed, pattern: "^one\\s+hundred\\s+(?:and\\s+)?five$") {
                return prefix + "105"
            }
            if let val = Self.spokenToInt(words) {
                return "\(prefix)\(val)"
            }
            return groups[0]
        }
    }

    private func applyBloodPressure(to text: String) -> String {
        return rewrite(text, with: bpRegex) { groups in
            // [1] = prefix, [2] = systolic words, [3] = diastolic words.
            let prefix = groups[1]
            let sysWords = groups[2]
            let diaWords = groups[3]
            if let sys = Self.spokenToInt(sysWords),
               let dia = Self.spokenToInt(diaWords) {
                return "\(prefix)\(sys)/\(dia)"
            }
            return groups[0]
        }
    }

    private func applySpO2(to text: String) -> String {
        return rewrite(text, with: spo2Regex) { groups in
            // [1] = prefix, [2] = spoken-number words. Trailing "percent" is
            // matched by the regex but lives outside the captured groups.
            let prefix = groups[1]
            let words = groups[2]
            if let val = Self.spokenToInt(words) {
                return "\(prefix)\(val)%"
            }
            return groups[0]
        }
    }

    private func applyRespiratoryRate(to text: String) -> String {
        return rewrite(text, with: rrRegex) { groups in
            let prefix = groups[1]
            let words = groups[2]
            if let val = Self.spokenToInt(words) {
                return "\(prefix)\(val)"
            }
            return groups[0]
        }
    }

    // MARK: - Helpers

    /// Apply a substitution pass: walk regex matches in `text`, hand each set
    /// of captured groups (as Strings) to `transform`, and splice the result
    /// back in. We process matches in reverse order so earlier match ranges
    /// remain valid as the string mutates.
    private func rewrite(
        _ text: String,
        with regex: NSRegularExpression,
        transform: ([String]) -> String
    ) -> String {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        if matches.isEmpty { return text }

        var result = text
        for match in matches.reversed() {
            // Collect every capture group as a String (or empty if missing).
            var groups: [String] = []
            groups.reserveCapacity(match.numberOfRanges)
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                if r.location == NSNotFound {
                    groups.append("")
                } else {
                    groups.append((result as NSString).substring(with: r))
                }
            }

            let replacement = transform(groups)

            // Splice replacement into the (mutating) result string.
            let nsResult = result as NSString
            let fullMatchRange = match.range(at: 0)
            // Guard against impossible drift; in practice this never trips
            // because we walk matches in reverse.
            guard fullMatchRange.location + fullMatchRange.length <= nsResult.length else {
                continue
            }
            result = nsResult.replacingCharacters(in: fullMatchRange, with: replacement)
        }
        return result
    }

    /// Match an NSRegularExpression-style pattern against `text` (case-insensitive).
    private func matchesIgnoreCase(_ text: String, pattern: String) -> Bool {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return r.firstMatch(in: text, options: [], range: range) != nil
    }
}
