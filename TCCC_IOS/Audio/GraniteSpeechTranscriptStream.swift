import Foundation
import TCCCAudio

/// `TranscriptStream` adapter for IBM Granite Speech ASR.
///
/// Sprint 1 (Granite Speech Foundation v3 §G1, 2026-05-10): this
/// actor wraps `TCCCAudio.GraniteSpeechRuntime` and surfaces it
/// through the existing `TranscriptStream` boundary so Apple Speech
/// + Parakeet stay first-class and Granite Speech becomes a
/// selectable alternate. `start(audioURL:)` is intentionally still
/// unavailable — G2 wires the actual `MLXAudioSTT.GraniteSpeechModel`
/// load + transcription, after which this method returns a real
/// `AsyncStream<RecognitionUpdate>`. G1's job is only to prove the
/// resolver + security-scope lifecycle works end-to-end.
///
/// Configuration prerequisite: the operator must have selected a
/// Granite Speech model folder via Settings →
/// "Select Granite Speech Model Folder", which writes a persistent
/// security-scoped bookmark under
/// `tccc.graniteSpeech.modelBookmarkV1`. Without it, `authorize()`
/// throws `backendUnavailable` and the recording flow never starts —
/// matching the no-RECORD-download policy already enforced by
/// `MLXBackend.HFHubCache`.
actor GraniteSpeechTranscriptStream: TranscriptStream {
    private let runtime: GraniteSpeechRuntime

    init(runtime: GraniteSpeechRuntime = GraniteSpeechRuntime(
        resolver: GraniteSpeechModelResolver(
            hfCacheLookup: { modelID in
                HFHubCache.directory(for: modelID).flatMap { dir in
                    HFHubCache.contains(modelId: modelID) ? dir : nil
                }
            }
        )
    )) {
        self.runtime = runtime
    }

    func authorize() async throws {
        do {
            _ = try await runtime.resolver.resolve()
        } catch let error as GraniteSpeechResolverError {
            throw TranscriptStreamError.backendUnavailable(
                "Granite Speech: \(error.errorDescription ?? "model not provided"). Open Settings → Select Granite Speech Model Folder."
            )
        } catch {
            throw TranscriptStreamError.backendUnavailable(
                "Granite Speech: \(error.localizedDescription)"
            )
        }
    }

    func prime() async throws {
        do {
            try await runtime.prime()
        } catch let error as GraniteSpeechRuntimeError {
            throw TranscriptStreamError.backendUnavailable(
                "Granite Speech: \(error.errorDescription ?? "prime failed")"
            )
        } catch let error as GraniteSpeechResolverError {
            throw TranscriptStreamError.backendUnavailable(
                "Granite Speech: \(error.errorDescription ?? "model not provided")"
            )
        } catch {
            throw TranscriptStreamError.backendUnavailable(
                "Granite Speech: \(error.localizedDescription)"
            )
        }
    }

    func unprime() async {
        await runtime.unload()
    }

    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> {
        // Sprint 1 G2 ships the model load + transcribe path through
        // `GraniteSpeechRuntime.transcribe(audioURL:)`. Live mic capture
        // through this `TranscriptStream` surface is a future phase
        // (mic → 16 kHz PCM chunks → continuous generateStream).
        // For G2, the DevTools "Granite Bake-off" view bypasses
        // TranscriptStream entirely and calls
        // `GraniteSpeechRuntime.transcribe(audioURL:)` on a bundled
        // fixture WAV. That validates the model on hardware without
        // the additional complexity of real-time chunked decoding.
        throw TranscriptStreamError.backendUnavailable(
            "Granite Speech: live RECORD path is not wired in this build. Use DevTools → Granite Bake-off to transcribe the bundled fixture, or wait for the G3 live-mic phase."
        )
    }

    func stop() async {
        // Nothing to stop — `start(audioURL:)` always throws in G1.
    }

    func stopImmediate() async {
        // Same as stop — no in-flight inference to interrupt.
    }
}
