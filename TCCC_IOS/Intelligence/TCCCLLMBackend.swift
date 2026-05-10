import Foundation

/// Backend abstraction for the on-device LLM use cases the app
/// currently runs through Apple Foundation Models:
///   1. Radio-script generation from a structured 9-line
///   2. 2–3 sentence encounter narrative
///   3. ZMIST handoff format
///
/// Per night-pass Track C (2026-05-05). Apple Foundation Models stays
/// the runtime default. Stub backends for LFM2.5-1.2B-Instruct and
/// Qwen 3 1.7B compile and ship in the binary but throw
/// `.notImplemented` until model weights are bundled / downloaded —
/// "on ice" exactly per the night plan.
///
/// Why both LFM2 and Qwen as stubs (not just the recommended LFM2):
///   - LFM Open License v1.0 (Liquid AI) has no AUP-style restrictions
///     on medical or military use; only a $10M revenue cap. Per
///     RESEARCH_LLM_SMALL.md it benches above Qwen 3 1.7B on IFEval
///     and runs faster on iPhone 17 Pro (59.7 vs 39.5 tok/s).
///   - Qwen 3 1.7B is the Apache-2.0 fallback if Liquid's license
///     turns out to have a clause we can't accept; keeping its stub
///     in place means the swap is a one-line backend-enum change.
///
/// Llama 3.2 deliberately NOT a backend option: its AUP forbids
/// "military, warfare" and "unauthorized practice of … medical/health"
/// — TCCC.ai is on both forks of that prohibition. (Per
/// RESEARCH_LLAMA32B.md.)
protocol TCCCLLMBackend: Sendable {
    /// Single-shot prompt → response. Instructions and prompt are
    /// separated so the wrapper can apply backend-specific system
    /// prompt formatting (Apple FoundationModels takes instructions
    /// at session creation; llama.cpp / MLX use a chat template).
    func generate(instructions: String, prompt: String) async throws -> String

    /// Backend availability — used by the UI to gate Generate buttons
    /// the same way the FMStatusBadge already gates the Apple
    /// Foundation Models case.
    var availability: BackendAvailability { get async }

    /// Human-readable backend name for Settings + status badge text.
    var displayName: String { get }
}

enum BackendAvailability: Sendable, Equatable {
    case available
    case downloading
    case modelNotProvided   // operator hasn't supplied model weights
    case deviceNotEligible
    case disabled            // user has turned the backend off
    case unknown
}

extension BackendAvailability {
    func message(for backendName: String) -> String {
        switch self {
        case .available:
            return ""
        case .downloading:
            return "\(backendName) is still downloading."
        case .modelNotProvided:
            return "\(backendName) model weights are not installed. Download in Settings before generating."
        case .deviceNotEligible:
            return "\(backendName) is not supported on this device."
        case .disabled:
            return "\(backendName) is disabled in Settings."
        case .unknown:
            return "\(backendName) is unavailable."
        }
    }
}

enum BackendError: Error, LocalizedError {
    /// Backend stub — model weights not yet bundled / downloaded.
    case notImplemented(backend: String)
    /// Backend selected but its model files aren't accessible.
    case modelNotProvided(backend: String)
    /// Inference failed at runtime.
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let b):
            return "\(b) backend is on ice — no model bundled in this build."
        case .modelNotProvided(let b):
            return "\(b) backend cannot run — provide a model file in Settings."
        case .generationFailed(let m):
            return "Generation failed: \(m)"
        }
    }
}

/// Test-only shaped backend for the Granite hot-seat path. It lives in
/// the app target so unit tests can exercise the same `TCCCLLMBackend`
/// boundary without adding a real model runtime or a network/download
/// path during Sprint 1.
struct MockGraniteHotSeatBackend: GraniteCandidatePatchBackend {
    let patch: GraniteCandidatePatch
    let displayName = "Mock Granite Hot Seat"

    var availability: BackendAvailability {
        .available
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(patch)
        return String(decoding: data, as: UTF8.self)
    }

    func generateCandidatePatch(
        instructions: String,
        prompt: String
    ) async throws -> GraniteCandidatePatch {
        patch
    }
}
