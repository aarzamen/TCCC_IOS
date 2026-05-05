import Foundation

/// Liquid AI LFM2.5-1.2B-Instruct backend (MLX 4-bit, ~660 MB on disk).
///
/// Per `RESEARCH_LLM_SMALL.md`, LFM2.5-1.2B is the recommended primary
/// alternative to Apple Foundation Models:
///   - LFM Open License v1.0 — no AUP-style medical/military prohibition
///     (only a $10M revenue cap)
///   - 59.7 tok/s on iPhone 17 Pro (vs 39.5 for Qwen 3 1.7B)
///   - Beats Qwen 3 on IFEval (74.89 vs 73.98) — the metric that matters
///     for our prompt-rigid generators (radio script / ZMIST / cleaner)
///   - Hybrid conv+attention architecture: only 6 attention layers, so a
///     much smaller KV cache than a pure-attention 1.2B equivalent.
///
/// Weights download from `mlx-community/LFM2-1.2B-4bit` on first use, or
/// via the Settings "Download" affordance which pre-fetches them. Forward
/// shell over `MLXBackend` — model id and display name are the only
/// per-product configuration.
actor LFM2LLMBackend: TCCCLLMBackend {

    private static let name = "Liquid LFM2.5 1.2B"
    private static let model = "mlx-community/LFM2-1.2B-4bit"

    private let backend = MLXBackend(displayName: name, modelId: model)

    nonisolated let displayName = LFM2LLMBackend.name

    var availability: BackendAvailability {
        get async { await backend.availability }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        try await backend.generate(instructions: instructions, prompt: prompt)
    }
}
