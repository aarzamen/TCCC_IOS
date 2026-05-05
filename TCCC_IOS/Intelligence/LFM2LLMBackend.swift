import Foundation

/// **Stub** — Liquid AI LFM2.5-1.2B-Instruct backend.
///
/// Per night-pass Track C / RESEARCH_LLM_SMALL.md, LFM2.5-1.2B is the
/// recommended primary alt LLM:
///   - LFM Open License v1.0: no AUP-style restriction on medical or
///     military use (only a $10M revenue cap)
///   - 660 MB at MLX 4-bit
///   - 59.7 tok/s on iPhone 17 Pro per Takkar Feb 2026 bench
///   - Beats Qwen 3 1.7B on IFEval (74.89 vs 73.98)
///   - Hybrid conv+attention architecture leaves more KV-cache
///     headroom than a pure-attention 1.7B
///
/// **On ice for now.** The integration path is documented but no MLX
/// runtime is wired and no model bundle ships. `generate()` throws
/// `.notImplemented` so a flipped backend setting fails loud and the
/// UI surfaces a clear "model needed" message.
///
/// Next step (when bundling): pull `mattt/AnyLanguageModel` (or
/// `mlx-swift-examples` directly), wire the `Session` API to MLX's
/// `LMModel`, swap the body of `generate(...)` to call it, and
/// surface a Settings affordance to import the .npz / .safetensors
/// bundle from Files.
actor LFM2LLMBackend: TCCCLLMBackend {

    let displayName = "Liquid LFM2.5 1.2B"

    var availability: BackendAvailability {
        // No runtime + no model = stays unavailable. Next-pass: read
        // from `AppState.lfm2ModelDirectory` (TBD) and probe.
        .modelNotProvided
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        throw BackendError.notImplemented(backend: displayName)
    }
}
