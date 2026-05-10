import Foundation

/// Owns the loaded Granite Speech model and the security-scoped URL
/// that anchors its weight files.
///
/// Sprint 1 (v3 §G1) ships only the resolver + scope lifecycle. The
/// real `MLXAudioSTT.GraniteSpeechModel.fromPretrained(...)` call lands
/// in §G2 once the resolver-to-loader binding has been verified on
/// physical iPhone. Until then, `prime()` resolves a URL and holds the
/// security scope; `transcribe(...)` is unimplemented.
///
/// Why an actor:
/// - Model loading + transcribe calls are async/IO-bound.
/// - The security-scope handle must be paired exactly once with
///   `start...` / `stop...`; reentrant prime calls would double-start
///   and leak. Actor serialization gives that guarantee for free.
/// - mlx-audio-swift's model object is not Sendable; isolating it
///   inside an actor avoids forcing it across concurrency boundaries.
public actor GraniteSpeechRuntime {
    public enum State: Sendable, Equatable {
        case idle
        case priming
        /// Primed state. `scopedURL` is non-nil only when the resolver
        /// returned a bookmark-source URL (the only case that requires
        /// a held scope handle).
        case primed(modelURL: URL, source: GraniteSpeechModelResolver.Source)
        case unloading
    }

    public let resolver: GraniteSpeechModelResolver
    private(set) public var state: State = .idle

    /// Held for the lifetime of `state == .primed` when the resolver's
    /// source is `.bookmark`. `nil` for bundle / HF-cache sources.
    private var scopedURL: URL?

    public init(resolver: GraniteSpeechModelResolver = GraniteSpeechModelResolver()) {
        self.resolver = resolver
    }

    /// Resolve the model URL and (if from a bookmark source) activate
    /// the security scope. Holds the scope until `unload()` or actor
    /// teardown. Idempotent if already primed — repeated calls return
    /// without re-activating the scope.
    public func prime() async throws {
        switch state {
        case .primed:
            return
        case .priming, .unloading:
            throw GraniteSpeechRuntimeError.busy
        case .idle:
            break
        }
        state = .priming
        do {
            let resolved = try await resolver.resolve()
            if resolved.needsScopeActivation {
                let didStart = resolved.url.startAccessingSecurityScopedResource()
                guard didStart else {
                    state = .idle
                    throw GraniteSpeechRuntimeError.scopeAccessDenied(url: resolved.url)
                }
                scopedURL = resolved.url
            }
            state = .primed(modelURL: resolved.url, source: resolved.source)
        } catch {
            state = .idle
            throw error
        }
    }

    /// Release the security scope (if held) and return to `.idle`.
    /// Safe to call from any state — no-op when already idle.
    public func unload() async {
        switch state {
        case .idle, .priming:
            return
        case .unloading:
            return
        case .primed:
            state = .unloading
            if let url = scopedURL {
                url.stopAccessingSecurityScopedResource()
                scopedURL = nil
            }
            state = .idle
        }
    }

    public var primedURL: URL? {
        if case .primed(let url, _) = state {
            return url
        }
        return nil
    }

    public var primedSource: GraniteSpeechModelResolver.Source? {
        if case .primed(_, let source) = state {
            return source
        }
        return nil
    }

    deinit {
        // Best-effort scope release if the actor is destroyed without
        // an explicit `unload()`. URL is Sendable, so accessing
        // `scopedURL` from the synchronous deinit is safe in Swift 6.
        scopedURL?.stopAccessingSecurityScopedResource()
    }
}

public enum GraniteSpeechRuntimeError: Error, Sendable, Equatable {
    case busy
    case scopeAccessDenied(url: URL)
    /// G2 placeholder — `start(audioURL:)` not yet implemented.
    case transcribeNotYetImplemented

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "Granite Speech runtime is mid-priming or unloading."
        case .scopeAccessDenied(let url):
            return "iOS denied security-scoped access for \(url.lastPathComponent). Re-select the model folder in Settings."
        case .transcribeNotYetImplemented:
            return "Granite Speech transcription is not implemented in this build (Sprint 1 G1 ships resolver + scope lifecycle only; G2 wires the model)."
        }
    }
}
