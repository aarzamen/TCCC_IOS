import Foundation
import TCCCLLM

/// Generic MLX-backed LLM backend. Wraps `AnyLanguageModel.MLXLanguageModel`
/// (re-exported through the local `TCCCLLM` shim package — see
/// `Packages/TCCCLLM/Package.swift` for why a shim is needed). The underlying
/// MLX loader can auto-download weights, but this wrapper refuses to generate
/// until the Settings download path has populated the local cache.
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
        guard HFHubCache.contains(modelId: modelId) else {
            throw BackendError.modelNotProvided(backend: displayName)
        }

        // Fresh session per call → no cross-casualty context bleed.
        // `LanguageModelSession(model:tools:instructions:)` accepts a
        // `String` directly (convenience init in
        // AnyLanguageModel/LanguageModelSession.swift line 40-46).
        let model = MLXLanguageModel(modelId: modelId)
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
        guard HFHubCache.contains(modelId: modelId) else {
            throw BackendError.modelNotProvided(backend: displayName)
        }

        let model = MLXLanguageModel(modelId: modelId)
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

    /// Trigger weight download into the HF Hub cache without performing a
    /// real generation. The model loader has to materialize weights before
    /// the first token, so a 1-token throwaway response is sufficient to
    /// populate the on-disk cache. `availability` flips to `.available`
    /// once this returns successfully (the snapshot directory is now
    /// non-empty).
    ///
    /// Surfaces any download / load error as `BackendError.generationFailed`
    /// for symmetry with `generate(...)`. The caller (typically
    /// `AppState.downloadBackendWeights`) is responsible for surfacing the
    /// failure to the operator via the system transcript or status pill.
    func prefetch() async throws {
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

/// Probes Hugging Face Hub's local snapshot cache. The cache is created
/// and populated by `mlx-swift-lm` (a transitive dep of AnyLanguageModel
/// via the MLX trait) using the standard `Hub.snapshot()` flow. Path
/// layout:
///
///   ~/Library/Caches/huggingface/hub/models--<owner>--<repo>/snapshots/<rev>/
///
/// We don't need to know the revision — checking that the
/// `models--<owner>--<repo>` directory exists with at least one snapshot
/// is sufficient signal for "weights are on disk and inference will not
/// block on a download."
///
/// Note: on iOS, `URLs(for: .cachesDirectory, in: .userDomainMask).first`
/// resolves to the app sandbox's `~/Library/Caches/<bundleId>/...`, which
/// is where `Hub` writes by default unless the host overrides `HF_HOME`.
/// If first-device test reveals weights landing somewhere else, update
/// `directory(for:)` to match.
enum HFHubCache {
    static func contains(modelId: String) -> Bool {
        guard let url = directory(for: modelId) else { return false }
        let snapshotsDir = url.appendingPathComponent("snapshots", isDirectory: true)
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                atPath: snapshotsDir.path
            )
        else {
            return false
        }
        return !entries.isEmpty
    }

    static func directory(for modelId: String) -> URL? {
        let safe = modelId.replacingOccurrences(of: "/", with: "--")
        let key = "models--\(safe)"
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        return caches?.appendingPathComponent(
            "huggingface/hub/\(key)",
            isDirectory: true
        )
    }
}
