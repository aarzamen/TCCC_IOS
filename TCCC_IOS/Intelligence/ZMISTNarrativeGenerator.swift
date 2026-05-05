import Foundation
import TCCCDomain
import TCCCReports

/// Builds a ZMIST handoff block as natural prose. Layered on top of
/// `TCCCReports.ZMISTGenerator` — the structured fallback runs first and is
/// passed to the SLM as the source of truth, so the SLM only rephrases.
/// Hallucinated fields can't slip in because the prompt explicitly anchors
/// to the deterministic Z/M/I/S/T values.
struct ZMISTNarrativeGenerator {

    static let systemInstructions = """
        You write ZMIST handoff blocks for combat casualty care.

        ZMIST format:
        - Z (zap/identifier): one line
        - M (mechanism of injury): one or two sentences
        - I (injuries sustained): bulleted or comma-separated
        - S (signs and symptoms / vitals): one paragraph
        - T (treatment given): bulleted or chronological

        Rules:
        - Use ONLY the fields provided in the structured input. Do not invent
          new fields, drugs, doses, or interventions.
        - Use medical shorthand where clinicians expect it (HR, BP, SpO₂, GCS,
          TQ, NPA, IV, IO, TXA).
        - Each section starts with its letter on a new line — "Z:", "M:", "I:",
          "S:", "T:".
        - Output ONLY the ZMIST block. No preamble, no markdown headers.
        """

    let backend: any TCCCLLMBackend
    private let fallback = ZMISTGenerator()

    init(backend: any TCCCLLMBackend) {
        self.backend = backend
    }

    func generate(for patient: PatientState?, casualtyId: String) async throws -> String {
        guard let patient else {
            return "Z: \(casualtyId)\nM: —\nI: —\nS: —\nT: —"
        }

        // Generate the deterministic structured block first, hand it to the
        // SLM as the source of truth, ask it to make the prose flow.
        let structured = fallback.generate(from: [patient]).formattedText

        let prompt = """
            Reformat the following structured ZMIST block as a clean,
            radio-ready handoff. Preserve every field exactly. Do not add
            new content. Write each section in tight medical prose suitable
            for spoken handoff.

            STRUCTURED:
            \(structured)

            Output the reformatted ZMIST now.
            """

        return try await backend.generate(
            instructions: Self.systemInstructions,
            prompt: prompt
        )
    }
}
