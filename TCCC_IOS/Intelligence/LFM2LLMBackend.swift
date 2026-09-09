import Foundation

/// LFM2 1.2B, MLX 4-bit. This shipped artifact is LFM2, not LFM2.5.
/// Its runtime speed and clinical fidelity require matched device measurements.
/// Generation uses validated local files; only explicit prefetch may download.
actor LFM2LLMBackend: TCCCLLMBackend {

    private static let name = "Liquid LFM2 1.2B"
    private static let model = "mlx-community/LFM2-1.2B-4bit"

    private let backend = MLXBackend(displayName: name, modelId: model)

    nonisolated let displayName = LFM2LLMBackend.name

    var availability: BackendAvailability {
        get async { await backend.availability }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        try await backend.generate(instructions: instructions, prompt: prompt)
    }

    /// Pre-fetch the LFM2 weights into the HF Hub cache. Pass-through to
    /// `MLXBackend.prefetch()`. Invoked from
    /// `AppState.downloadBackendWeights(_:)` when the operator taps
    /// DOWNLOAD in Settings.
    func prefetch() async throws {
        try await backend.prefetch()
    }
}
