import Foundation
import TCCCLLM

/// Generic MLX-backed LLM backend. Wraps `AnyLanguageModel.MLXLanguageModel`
/// (re-exported through the local `TCCCLLM` shim package — see
/// `Packages/TCCCLLM/Package.swift` for why a shim is needed). The MLX
/// model auto-downloads its weights from the Hugging Face Hub on first
/// use and caches them locally.
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
    /// `.modelNotProvided` does NOT mean inference will fail — the
    /// underlying MLX model auto-downloads on first request. It only
    /// means the next `generate(...)` will block on a network round-trip
    /// before producing a token. UI should gate accordingly.
    var availability: BackendAvailability {
        get async {
            HFHubCache.contains(modelId: modelId) ? .available : .modelNotProvided
        }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
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
