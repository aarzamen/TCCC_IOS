import Foundation
import FoundationModels

/// Thin wrapper around Apple's on-device Foundation Model.
///
/// Why an actor: LanguageModelSession is not `Sendable` and we need a single
/// reusable session per "task" (radio script, narrative, etc.) so context
/// across calls is coherent. Wrapping it in an actor gives us isolation and
/// a clean async API surface.
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
    private var session: LanguageModelSession?

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

    /// Send a prompt, get back plain text. Reuses the same session across
    /// calls so context (instructions, prior turns) carries forward.
    func generate(prompt: String) async throws -> String {
        let session = try ensureSession()
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            throw ModelError.generationFailed(error.localizedDescription)
        }
    }

    /// Reset the conversation. Call between unrelated tasks (e.g., switching
    /// from MEDEVAC script generation to encounter narrative) so prior prompt
    /// context doesn't leak.
    func reset() {
        session = nil
    }

    private func ensureSession() throws -> LanguageModelSession {
        if let session { return session }

        let availability = SystemLanguageModel.default.availability
        guard availability == .available else {
            throw ModelError.unavailable(reason: String(describing: availability))
        }

        let session = LanguageModelSession(instructions: instructions)
        self.session = session
        return session
    }
}
