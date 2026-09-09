import Foundation

/// Qwen 3 1.7B, MLX 4-bit. Apache-2.0 alternate backend.
/// Vendor benchmark claims are not measured TCCC device results.
/// Generation uses validated local files; only explicit prefetch may download.
actor QwenLLMBackend: TCCCLLMBackend {

    private static let name = "Qwen 3 1.7B"
    private static let model = "mlx-community/Qwen3-1.7B-4bit"

    private let backend = MLXBackend(displayName: name, modelId: model)

    nonisolated let displayName = QwenLLMBackend.name

    var availability: BackendAvailability {
        get async { await backend.availability }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        try await backend.generate(instructions: instructions, prompt: prompt)
    }

    /// Pre-fetch the Qwen 3 weights into the HF Hub cache. Pass-through to
    /// `MLXBackend.prefetch()`. Invoked from
    /// `AppState.downloadBackendWeights(_:)` when the operator taps
    /// DOWNLOAD in Settings.
    func prefetch() async throws {
        try await backend.prefetch()
    }
}
