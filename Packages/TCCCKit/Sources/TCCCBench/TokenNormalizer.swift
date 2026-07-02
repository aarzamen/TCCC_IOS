import Foundation

/// Deterministic token normalization so a reference transcript and an ASR
/// hypothesis compare fairly: lowercase, punctuation stripped, number words
/// folded to digits, digit strings ≥3 chars split to single digits (grid
/// coordinates are spoken digit-by-digit), tens+units combined ("thirty
/// two" → "32"), and caller-supplied fold runs merged ("t x a" → "txa").
public enum TokenNormalizer {
    static let numberWords: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3",
        "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
        "nine": "9", "niner": "9", "ten": "10", "eleven": "11",
        "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15",
        "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19",
        "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50",
        "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
    ]

    public static func tokens(_ text: String, extraFolds: [[String]] = []) -> [String] {
        // 1. Lowercase; hyphens/slashes become spaces; drop everything that
        //    is not a letter, digit, or space (apostrophes vanish: we're→were).
        let lowered = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
        var cleaned = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                cleaned.unicodeScalars.append(scalar)
            }
        }
        var toks = cleaned.split(separator: " ").map(String.init)

        // 2. Number words → digits.
        toks = toks.map { numberWords[$0] ?? $0 }

        // 3. Combine tens + unit ("30","2" → "32").
        var combined: [String] = []
        var i = 0
        while i < toks.count {
            if i + 1 < toks.count,
               let tens = Int(toks[i]), tens % 10 == 0, (20...90).contains(tens),
               let unit = Int(toks[i + 1]), (1...9).contains(unit) {
                combined.append(String(tens + unit))
                i += 2
            } else {
                combined.append(toks[i])
                i += 1
            }
        }
        toks = combined

        // 4. Split pure-digit tokens of length ≥3 into single digits.
        toks = toks.flatMap { tok -> [String] in
            if tok.count >= 3, tok.allSatisfy(\.isNumber) {
                return tok.map(String.init)
            }
            return [tok]
        }

        // 5. Apply fold runs (["t","x","a","txa"]: run of prefix → last).
        for fold in extraFolds where fold.count >= 2 {
            let run = fold.dropLast().map { $0.lowercased() }
            let replacement = fold.last!.lowercased()
            var out: [String] = []
            var j = 0
            while j < toks.count {
                if j + run.count <= toks.count,
                   Array(toks[j..<(j + run.count)]) == run {
                    out.append(replacement)
                    j += run.count
                } else {
                    out.append(toks[j])
                    j += 1
                }
            }
            toks = out
        }
        return toks
    }
}
