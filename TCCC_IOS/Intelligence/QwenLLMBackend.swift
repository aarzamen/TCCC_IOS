import Foundation

/// **Stub** — Qwen 3 1.7B backend.
///
/// Per night-pass Track C / RESEARCH_LLM_SMALL.md, Qwen 3 1.7B is
/// the Apache-2.0 fallback for the alt-LLM slot:
///   - Apache 2.0 (cleanest license; no AUP traps)
///   - Available in MLX Q4 (~1.0 GB) and Q5 (~1.2 GB)
///   - 39.5 tok/s on iPhone 17 Pro
///   - 73.98 IFEval
///
/// **On ice.** Same shape as LFM2LLMBackend — implementation lands
/// the moment a Q4/Q5 GGUF or MLX bundle is on the device.
///
/// We keep both LFM2 and Qwen stubs in the binary so swapping
/// "primary alt" between them is a one-line backend-enum change in
/// AppState.llmBackend, not a code rewrite, when the operator field-
/// tests preference shifts.
actor QwenLLMBackend: TCCCLLMBackend {

    let displayName = "Qwen 3 1.7B"

    var availability: BackendAvailability { .modelNotProvided }

    func generate(instructions: String, prompt: String) async throws -> String {
        throw BackendError.notImplemented(backend: displayName)
    }
}
