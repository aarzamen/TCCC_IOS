import Foundation
import FoundationModels

/// Thin wrapper around Apple's on-device Foundation Model.
///
/// Why an actor: LanguageModelSession is not `Sendable`. We hand out a fresh
/// session per `generate(prompt:)` call so unrelated generations (radio script,
/// ZMIST, narrative, transcript cleanup) and unrelated casualties never share
/// conversational context. The actor isolation gives us a clean async API
/// surface and a single place to centralise availability checks.
///
/// RF Ghost: the entire Foundation Models stack runs on-device on the Apple
/// Neural Engine. No network calls. Apple's privacy guarantee + our forbidden
/// networking framework list make this the only acceptable LLM path.
actor TCCCLanguageModel {

    enum ModelError: Error, LocalizedError {
        case unavailable(reason: String)
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return "Foundation Model unavailable: \(reason)"
            case .generationFailed(let msg): return "Generation failed: \(msg)"
            }
        }
    }

    private let instructions: String

    init(instructions: String) {
        self.instructions = instructions
    }

    /// Returns true iff the system Foundation Model is currently available.
    /// Reports the reason it's not when relevant — e.g., Apple Intelligence
    /// disabled in Settings, model still downloading, or device unsupported.
    static func availability() -> SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Every call gets a fresh session — no context bleeds between casualties
    /// or between generation kinds (radio / ZMIST / narrative / cleanup).
    func generate(prompt: String) async throws -> String {
        let availability = SystemLanguageModel.default.availability
        guard availability == .available else {
            throw ModelError.unavailable(reason: String(describing: availability))
        }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            throw ModelError.generationFailed(error.localizedDescription)
        }
    }
}
