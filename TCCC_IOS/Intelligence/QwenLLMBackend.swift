import Foundation

/// Qwen 3 1.7B backend (MLX 4-bit, ~968 MB on disk).
///
/// Per `RESEARCH_LLM_SMALL.md` §6, Qwen 3 1.7B is the Apache-2.0 fallback
/// for the alt-LLM slot:
///   - Apache 2.0 — cleanest license, no AUP traps (in contrast to Llama's
///     AUP, which forbids both medical and military use)
///   - 39.5 tok/s on iPhone 17 Pro (vs 59.7 for LFM2.5 1.2B — slower)
///   - 73.98 IFEval (vs LFM2's 74.89 — close, slightly behind)
///   - Larger parameter count brings stronger general reasoning but also
///     a heavier KV cache. Treated as the contingency backend if Liquid's
///     license terms become untenable, or if field testing reveals LFM2
///     drift on combat-medic vocabulary that Qwen handles better.
///
/// Weights download from `mlx-community/Qwen3-1.7B-4bit` on first use, or
/// via the Settings "Download" affordance.
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
