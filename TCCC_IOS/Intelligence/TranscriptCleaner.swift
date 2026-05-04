import Foundation

/// Runs the raw ASR transcript through the on-device language model to fix
/// the predictable mistakes — drug names, anatomy, vital numbers spoken in
/// shorthand, military abbreviations the recognizer mishears.
///
/// Original transcript is preserved on the AppState side so the medic can
/// always toggle back to the raw capture.
struct TranscriptCleaner {

    static let systemInstructions = """
        You clean up speech-to-text transcripts of combat medics narrating
        casualty care.

        Rules:
        - Fix obvious mishearings: drug names (e.g., "tea-x-a" → "TXA",
          "moxifloxin" → "moxifloxacin"), anatomy ("femer" → "femur",
          "thye" → "thigh"), military shorthand ("nine line" → "9-Line",
          "tee see see see" → "TCCC", "med-evac" → "MEDEVAC").
        - Normalize spoken numbers: "one ten" → "110", "ninety over sixty"
          → "90/60", but ONLY when the context is clearly a vital sign.
          When in doubt, leave numbers as-is.
        - Preserve speaker turns. Do NOT merge multiple lines into one.
        - Preserve sentence structure. Do NOT shorten or expand prose.
        - Do NOT add commentary, corrections, or context the medic didn't say.
        - Do NOT change the meaning. If a word is unclear, leave it alone.

        Output format: each line on its own line, in this exact format:
        [HH:MM] SPEAKER: text

        Match the input format exactly. One line per input line. No headers,
        no preamble, no markdown.
        """

    let model: TCCCLanguageModel

    init() {
        self.model = TCCCLanguageModel(instructions: Self.systemInstructions)
    }

    /// Clean the transcript. Returns a new array of `TranscriptLine` with
    /// the same `id`s, timestamps, speakers, and isPartial flags — only the
    /// `text` fields are updated.
    func clean(_ lines: [TranscriptLine]) async throws -> [TranscriptLine] {
        guard !lines.isEmpty else { return lines }

        let formatted = lines.map { line -> String in
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            let ts = f.string(from: line.timestamp)
            return "[\(ts)] \(line.speaker.rawValue.uppercased()): \(line.text)"
        }.joined(separator: "\n")

        let prompt = """
            Clean the following transcript. One line out per line in.

            \(formatted)

            Output the cleaned transcript now.
            """

        let response = try await model.generate(prompt: prompt)
        return Self.merge(originals: lines, cleanedText: response)
    }

    /// Parse the model's line-formatted output and merge cleaned text back
    /// into the original lines (keeping IDs, timestamps, speakers stable).
    /// If parsing fails or the line counts don't match, falls back to the
    /// originals untouched on a per-line basis.
    static func merge(originals: [TranscriptLine], cleanedText: String) -> [TranscriptLine] {
        let cleanedLines = cleanedText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        guard cleanedLines.count == originals.count else {
            // Best-effort: try to match by speaker pattern. If that doesn't
            // work either, return originals so we don't lose data.
            return originals
        }

        return zip(originals, cleanedLines).map { (orig, cleaned) in
            // Strip the "[HH:MM] SPEAKER: " prefix the model emits.
            let stripped = stripPrefix(from: cleaned) ?? cleaned
            return TranscriptLine(
                id: orig.id,
                speaker: orig.speaker,
                text: stripped,
                timestamp: orig.timestamp,
                isPartial: orig.isPartial
            )
        }
    }

    private static func stripPrefix(from line: String) -> String? {
        // Pattern: "[12:34] MEDIC: text..."
        guard let colonRange = line.range(of: ":", options: [], range: nil, locale: nil) else {
            return nil
        }
        // Find the LAST colon that ends with ": " — that separates the
        // speaker from the body. The first colon is in the timestamp.
        let speakerColonRange = line.range(of: ": ")
        if let s = speakerColonRange {
            return String(line[s.upperBound...])
        }
        // Fallback: split on first ": "
        let after = line[colonRange.upperBound...]
        return String(after).trimmingCharacters(in: .whitespaces)
    }
}
