import Foundation

/// Generates a natural-language radio call script from a structured
/// `NineLineForm`. Uses the on-device Foundation Model to phrase the
/// 9-Line as a real combat-radio transmission ready to read aloud.
///
/// This is intentionally a *prose generation* layer on top of the
/// already-validated 9-Line. The model never decides clinical state — it
/// only rephrases the structured fields. If the model goes off-script
/// (hallucinates a Line 10, invents a callsign, etc.) the medic still has
/// the structured form on screen as ground truth.
struct RadioScriptGenerator {

    static let systemInstructions = """
        You format casualty MEDEVAC requests for combat radio communication.

        Rules:
        - Be terse and tactical. This is a real radio call, not a memo.
        - Open with: "<receiver>, <receiver>, this is <callsign>. Send MEDEVAC, over."
        - Then enumerate the lines: "Line 1, ..." through "Line 9, ...".
        - For numeric values, prefer phonetic (e.g., "tree" for 3, "fife" for 5, "niner" for 9).
        - Spell out grids one digit at a time: "four two sierra whiskey delta, eight seven two one, four three five six".
        - Use NATO phonetic for letter codes: "alpha" for A, "bravo" for B, etc.
        - End with: "How copy, over."
        - Never invent fields. If a field is missing, say "unknown" or skip the line.
        - Do not add commentary, preface, or sign-off beyond what's specified.
        - Output ONLY the call script — no markdown, no quotes, no labels like "RADIO CALL:".
        """

    let backend: any TCCCLLMBackend

    init(backend: any TCCCLLMBackend) {
        self.backend = backend
    }

    /// Build a radio script from the given 9-Line form.
    func generate(
        from form: NineLineForm,
        callsign: String = "HAVOC TWO ACTUAL",
        receiver: String = "DUSTOFF SIX"
    ) async throws -> String {
        let lines = form.entries.map { entry in
            "Line \(entry.number) (\(entry.label)): \(entry.value)"
        }.joined(separator: "\n")

        let prompt = """
            Format the following 9-Line MEDEVAC for a combat-radio transmission.

            Receiver: \(receiver)
            Callsign: \(callsign)

            \(lines)

            Generate the radio call now. Output only the script.
            """

        return try await backend.generate(
            instructions: Self.systemInstructions,
            prompt: prompt
        )
    }
}
