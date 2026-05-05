import Foundation
import FoundationModels

/// Apple Foundation Models backend conformer for `TCCCLLMBackend`.
/// Wraps the existing `TCCCLanguageModel` actor pattern so the four
/// generators (radio, narrative, ZMIST, cleaner) can swap to a
/// different backend at runtime per night-pass Track C.
///
/// This is the **default** backend — operator does nothing and Apple
/// Foundation Models is what runs. The four generators
/// (`RadioScriptGenerator`, `EncounterNarrativeGenerator`,
/// `ZMISTNarrativeGenerator`, `TranscriptCleaner`) all consume
/// `any TCCCLLMBackend` per call (vended by `AppState.currentBackend`),
/// so flipping the Settings backend toggle swaps engines at runtime.
actor AppleFoundationLLMBackend: TCCCLLMBackend {

    let displayName = "Apple Foundation Models"

    private var session: LanguageModelSession?
    private var lastInstructions: String?

    var availability: BackendAvailability {
        let a = SystemLanguageModel.default.availability
        switch a {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:           return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .disabled
            case .modelNotReady:               return .downloading
            @unknown default:                  return .unknown
            }
        @unknown default:
            return .unknown
        }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        // Reset the session if instructions changed — the FoundationModels
        // session captures instructions at construction, so different
        // tasks (radio vs narrative vs ZMIST vs cleaner) need their own.
        if session == nil || lastInstructions != instructions {
            session = LanguageModelSession(instructions: instructions)
            lastInstructions = instructions
        }
        guard let session else {
            throw BackendError.generationFailed("session unavailable")
        }
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            throw BackendError.generationFailed(error.localizedDescription)
        }
    }
}
