import Foundation
import TCCCLLM

/// Generic MLX-backed LLM backend. Wraps `AnyLanguageModel.MLXLanguageModel`
/// (re-exported through the local `TCCCLLM` shim package — see
/// `Packages/TCCCLLM/Package.swift` for why a shim is needed). The underlying
/// MLX loader can auto-download weights, but this wrapper refuses to generate
/// until a complete bundled, installed or cached model directory resolves.
///
/// The actor itself is stateless across `generate(...)` calls — every call
/// constructs a fresh `LanguageModelSession`, so context never bleeds
/// between casualties or between generation kinds. This matches the
/// invariant `TCCCLanguageModel` already established for Apple Foundation
/// Models (sprint B1, "fresh session per call").
///
/// Two concrete instantiations live in `LFM2LLMBackend` and
/// `QwenLLMBackend`. Both forward straight through to this actor with
/// their model id and display name baked in.
actor MLXBackend: TCCCLLMBackend {
    nonisolated let displayName: String
    private let modelId: String

    init(displayName: String, modelId: String) {
        self.displayName = displayName
        self.modelId = modelId
    }

    /// Reports whether the model snapshot is already cached locally.
    /// Cached → `.available`. Not cached → `.modelNotProvided` (the
    /// operator can tap "Download" in Settings to pre-fetch).
    ///
    /// `.modelNotProvided` means inference is blocked until the operator
    /// taps the Settings download affordance. This keeps first-use network
    /// traffic explicit instead of smuggling it through a Generate button.
    var availability: BackendAvailability {
        get async {
            HFHubCache.contains(modelId: modelId) ? .available : .modelNotProvided
        }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        guard let directory = HFHubCache.directory(for: modelId) else {
            throw BackendError.modelNotProvided(backend: displayName)
        }

        // Fresh session per call → no cross-casualty context bleed.
        // `LanguageModelSession(model:tools:instructions:)` accepts a
        // `String` directly (convenience init in
        // AnyLanguageModel/LanguageModelSession.swift line 40-46).
        let model = MLXLanguageModel(modelId: modelId, directory: directory)
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            throw BackendError.generationFailed(
                "\(displayName): \(error.localizedDescription)"
            )
        }
    }

    /// Structured generation path for hot-seat JSON. This still uses the
    /// same cache gate as plain text generation, so a model cannot download
    /// from a Generate / Review path. AnyLanguageModel's MLX backend uses
    /// constrained JSON generation when the requested type is `Generable`.
    func generateStructured<Content>(
        instructions: String,
        prompt: String,
        generating type: Content.Type
    ) async throws -> Content where Content: Generable, Content: Sendable {
        guard let directory = HFHubCache.directory(for: modelId) else {
            throw BackendError.modelNotProvided(backend: displayName)
        }

        let model = MLXLanguageModel(modelId: modelId, directory: directory)
        let session = LanguageModelSession(model: model, instructions: instructions)
        var options = GenerationOptions()
        options.maximumResponseTokens = 768

        do {
            let response = try await session.respond(
                to: prompt,
                generating: type,
                includeSchemaInPrompt: true,
                options: options
            )
            return response.content
        } catch {
            throw BackendError.generationFailed(
                "\(displayName): \(error.localizedDescription)"
            )
        }
    }

    /// Explicit Settings preparation. This is the only model-ID loading path,
    /// and may download; ordinary generation always supplies a local directory.
    func prefetch() async throws {
        if HFHubCache.contains(modelId: modelId) { return }
        let model = MLXLanguageModel(modelId: modelId)
        let session = LanguageModelSession(model: model, instructions: "warmup")
        var opts = GenerationOptions()
        opts.maximumResponseTokens = 1
        do {
            _ = try await session.respond(to: "hi", options: opts)
        } catch {
            throw BackendError.generationFailed(
                "\(displayName) download/warmup: \(error.localizedDescription)"
            )
        }
    }
}

/// Compatibility bridge: returns a validated model leaf, never a repository parent.
/// Generation always passes this URL into the directory-only MLX loader.
enum HFHubCache {
    static func contains(modelId: String) -> Bool { directory(for: modelId) != nil }
    static func directory(for modelId: String) -> URL? {
        OfflineModelAssets.resolve(modelID: modelId)
    }
}
