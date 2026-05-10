import Foundation
import MLXAudioCore
import MLXAudioSTT

/// Owns the loaded Granite Speech model + the security-scoped URL
/// that anchors its weight files (Sprint 1 v3 §G1 lifecycle, §G2
/// model load + transcribe).
///
/// Why an actor:
/// - Model loading + transcription are async/IO-bound.
/// - The security-scope handle must be paired exactly once with
///   `start...` / `stop...`; reentrant prime calls would double-start
///   and leak. Actor serialization gives that guarantee for free.
/// - mlx-audio-swift's model object is not `Sendable`; isolating it
///   inside an actor avoids forcing it across concurrency boundaries.
public actor GraniteSpeechRuntime {
    public enum State: Sendable, Equatable {
        case idle
        case priming
        /// Primed state. `scopedURL` is non-nil only when the resolver
        /// returned a bookmark-source URL.
        case primed(modelURL: URL, source: GraniteSpeechModelResolver.Source)
        case unloading
    }

    public let resolver: GraniteSpeechModelResolver
    private(set) public var state: State = .idle

    /// Held for the lifetime of `state == .primed` when the resolver's
    /// source is `.bookmark`. `nil` for bundle / HF-cache sources.
    private var scopedURL: URL?

    /// The loaded MLX model. Nil when not primed. Not Sendable, hence
    /// kept inside the actor's isolation.
    private var loadedModel: GraniteSpeechModel?

    /// Memory readings captured around `prime()` for diagnostics. Set
    /// when the load completes; reset on `unload()`.
    public private(set) var primeMemoryDelta: PrimeMemoryDelta?

    public struct PrimeMemoryDelta: Sendable, Equatable {
        public let physFootprintBeforeBytes: UInt64
        public let physFootprintAfterBytes: UInt64
        public let availableBeforeBytes: UInt64
        public let availableAfterBytes: UInt64
        public let loadDurationSeconds: Double

        public var physFootprintDeltaMB: Double {
            (Double(physFootprintAfterBytes) - Double(physFootprintBeforeBytes)) / 1_048_576.0
        }
    }

    public init(resolver: GraniteSpeechModelResolver = GraniteSpeechModelResolver()) {
        self.resolver = resolver
    }

    /// Resolve the model URL, activate security scope (if from
    /// bookmark), and load `GraniteSpeechModel` into memory.
    /// Idempotent if already primed.
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

        let resolved: GraniteSpeechModelResolver.Resolved
        do {
            resolved = try await resolver.resolve()
        } catch {
            state = .idle
            throw error
        }

        if resolved.needsScopeActivation {
            let didStart = resolved.url.startAccessingSecurityScopedResource()
            guard didStart else {
                state = .idle
                throw GraniteSpeechRuntimeError.scopeAccessDenied(url: resolved.url)
            }
            scopedURL = resolved.url
        }

        let memoryBefore = MemoryMonitor.reading()
        let loadStart = Date()
        let model: GraniteSpeechModel
        do {
            model = try await GraniteSpeechModelLoader.loadFromModelDirectory(resolved.url)
        } catch {
            if let url = scopedURL {
                url.stopAccessingSecurityScopedResource()
                scopedURL = nil
            }
            state = .idle
            throw GraniteSpeechRuntimeError.loadFailed(
                underlying: error.localizedDescription
            )
        }
        let loadEnd = Date()
        let memoryAfter = MemoryMonitor.reading()

        loadedModel = model
        primeMemoryDelta = PrimeMemoryDelta(
            physFootprintBeforeBytes: memoryBefore.physFootprintBytes,
            physFootprintAfterBytes: memoryAfter.physFootprintBytes,
            availableBeforeBytes: memoryBefore.availableBytes,
            availableAfterBytes: memoryAfter.availableBytes,
            loadDurationSeconds: loadEnd.timeIntervalSince(loadStart)
        )
        state = .primed(modelURL: resolved.url, source: resolved.source)
    }

    /// Release the loaded model, the security scope, and reset to
    /// `.idle`. Safe to call from any state.
    public func unload() async {
        switch state {
        case .idle, .priming:
            return
        case .unloading:
            return
        case .primed:
            state = .unloading
            loadedModel = nil
            if let url = scopedURL {
                url.stopAccessingSecurityScopedResource()
                scopedURL = nil
            }
            primeMemoryDelta = nil
            state = .idle
        }
    }

    /// Transcribe a pre-recorded audio file. Streams `STTGeneration`
    /// events (`.token / .info / .result`) so callers can render
    /// partial transcripts as the model decodes. Audio is loaded via
    /// `MLXAudioCore.loadAudioArray(from:)`, which handles
    /// re-sampling to the encoder's required 16 kHz mono.
    ///
    /// `prompt` defaults to `GraniteSpeechPrompt.asr` (TCCC keyword
    /// biasing). Pass `nil` to bypass biasing for a baseline run.
    public func transcribe(
        audioURL: URL,
        prompt: String? = GraniteSpeechPrompt.asr,
        maxTokens: Int = 4096,
        temperature: Float = 0.0
    ) async throws -> AsyncThrowingStream<STTGeneration, Error> {
        guard case .primed = state else {
            throw GraniteSpeechRuntimeError.notPrimed
        }
        guard let model = loadedModel else {
            throw GraniteSpeechRuntimeError.notPrimed
        }

        // Load audio off the actor's hot path. `loadAudioArray` does
        // disk I/O + AVAudioFile decode + resampling; cheap enough to
        // keep on the same actor for now, but if it blocks too long
        // on long fixtures we move it to a Task.detached later.
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)

        return model.generateStream(
            audio: audio,
            maxTokens: maxTokens,
            temperature: temperature,
            prompt: prompt,
            language: nil
        )
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

    public var isPrimed: Bool {
        if case .primed = state { return true }
        return false
    }
}

public enum GraniteSpeechRuntimeError: Error, LocalizedError, Sendable, Equatable {
    case busy
    case scopeAccessDenied(url: URL)
    case notPrimed
    case loadFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "Granite Speech runtime is mid-priming or unloading."
        case .scopeAccessDenied(let url):
            return "iOS denied security-scoped access for \(url.lastPathComponent). Re-select the model folder in Settings."
        case .notPrimed:
            return "Granite Speech runtime must be primed before transcription. Call prime() first."
        case .loadFailed(let m):
            return "Granite Speech model load failed: \(m)"
        }
    }
}
