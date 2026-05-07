import Foundation

/// IBM Granite 4.0 H 1B Base backend for the hot-seat text pass.
///
/// This is an explicit alternate backend, never the default. It uses the
/// existing MLX cache gate, so generation refuses missing weights and only
/// the Settings DOWNLOAD path can prefetch the Hugging Face artifact.
actor GraniteTextLLMBackend: GraniteCandidatePatchBackend {
    static let modelId = "mlx-community/granite-4.0-h-1b-base-4bit"
    private static let name = "IBM Granite 4.0 H 1B Base"

    private let backend = MLXBackend(displayName: name, modelId: modelId)

    nonisolated let displayName = GraniteTextLLMBackend.name

    var availability: BackendAvailability {
        get async { await backend.availability }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        try await backend.generate(instructions: instructions, prompt: prompt)
    }

    func generateCandidatePatch(
        instructions: String,
        prompt: String
    ) async throws -> GraniteCandidatePatch {
        let generated = try await backend.generateStructured(
            instructions: instructions,
            prompt: prompt,
            generating: GraniteGeneratedCandidatePatch.self
        )
        return generated.makeCandidatePatch()
    }

    func prefetch() async throws {
        try await backend.prefetch()
    }
}
