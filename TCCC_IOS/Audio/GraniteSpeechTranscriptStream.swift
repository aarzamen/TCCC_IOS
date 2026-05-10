import AVFoundation
import Foundation
import TCCCAudio
@preconcurrency import AVFAudio

/// `TranscriptStream` adapter for IBM Granite Speech ASR.
///
/// Sprint 1 G3 (2026-05-10): live-mic path lands as **record-then-transcribe**
/// — the actor opens an `AVAudioEngine` tap, writes captured audio to AAC
/// (matching the existing Apple Speech / Parakeet `.m4a` archive format),
/// and on `stop()` runs `GraniteSpeechRuntime.transcribe(audioURL:)` over
/// the captured file before emitting a single final `RecognitionUpdate`.
/// Real-time chunked decode is parked for Sprint 2/3 — the long-form
/// encoder crash documented in `Packages/TCCCAudio/CLAUDE.md` G2 §"Known
/// limitations" requires chunked-encode work that we'd rather inform with
/// the prior-repo audio-buffering research before writing.
///
/// Configuration prerequisite: the operator selected a Granite Speech
/// model folder via Settings → "Select Granite Speech Model Folder",
/// which writes a persistent security-scoped bookmark under
/// `tccc.graniteSpeech.modelBookmarkV1`. Without it, `authorize()` throws
/// `backendUnavailable` and the recording flow never starts.
///
/// Mic-capture pattern is cribbed from `SpeechRecognizer.swift`:
/// AVAudioEngine + tap on input node + AAC `AVAudioFile` writer routed
/// through `ProtectedWrite` so the casualty audio at rest stays under
/// `NSFileProtectionComplete` (CLAUDE.md hard constraint #3).
actor GraniteSpeechTranscriptStream: TranscriptStream {
    private let runtime: GraniteSpeechRuntime
    private weak var levels: AudioLevels?
    private let gainProvider: @Sendable () -> Float

    private let engine = AVAudioEngine()
    private var inputFormat: AVAudioFormat?
    private var audioFile: AVAudioFile?
    private var recordedURL: URL?
    private var continuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var isPrimed: Bool = false
    private var isRecording: Bool = false
    private var transcribeTask: Task<Void, Never>?

    init(
        runtime: GraniteSpeechRuntime = GraniteSpeechRuntime(
            resolver: GraniteSpeechModelResolver(
                hfCacheLookup: { modelID in
                    HFHubCache.directory(for: modelID).flatMap { dir in
                        HFHubCache.contains(modelId: modelID) ? dir : nil
                    }
                }
            )
        ),
        levels: AudioLevels? = nil,
        gainProvider: @escaping @Sendable () -> Float = { 1.0 }
    ) {
        self.runtime = runtime
        self.levels = levels
        self.gainProvider = gainProvider
    }

    // MARK: - TranscriptStream

    func authorize() async throws {
        // Mic permission first — needed regardless of model state.
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            throw TranscriptStreamError.microphoneDenied
        }
        // Then the resolver — surfaces "select a model folder" path
        // before any RECORD tap can fail surprisingly.
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
        guard !isPrimed else { return }
        do {
            try await runtime.prime()
            isPrimed = true
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
        if isRecording { await stopImmediate() }
        if isPrimed {
            await runtime.unload()
            isPrimed = false
        }
    }

    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> {
        if !isPrimed { try await prime() }
        guard !isRecording else { throw TranscriptStreamError.alreadyRunning }

        try configureSession()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format

        let url = audioURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("granite-live-\(UUID().uuidString).m4a")
        recordedURL = url

        // AVAudioFile writes inherit Data Protection from the file we
        // pre-create with NSFileProtectionComplete. Mirrors the path
        // SpeechRecognizer + ParakeetTranscriptStream already use.
        do {
            try ProtectedWrite.createEmpty(at: url)
            let file = try AVAudioFile(
                forWriting: url,
                settings: AudioCaptureConfig.aacOutputSettings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            self.audioFile = file
        } catch {
            // Non-fatal — we can still transcribe live audio out of a
            // temp WAV if AAC setup failed. Fall back to a temp WAV.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("granite-live-\(UUID().uuidString).wav")
            recordedURL = tempURL
            self.audioFile = try? AVAudioFile(
                forWriting: tempURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        }

        let weakLevels = self.levels
        let gain = gainProvider
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let copy = Self.copyBuffer(buffer) else { return }
            let g = gain()
            if g != 1.0 {
                Self.applyGain(copy, gain: g)
            }
            let rms = Self.computeRMS(copy)
            if let weakLevels {
                Task { @MainActor in weakLevels.ingest(rms) }
            }
            Task { [weak self] in
                await self?.ingestBuffer(copy)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioFile = nil
            recordedURL = nil
            throw TranscriptStreamError.engineFailed(error.localizedDescription)
        }
        isRecording = true

        let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() async {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )

        // Close the file before MLXAudio reads it.
        let url = recordedURL
        audioFile = nil
        if let url {
            try? ProtectedWrite.markProtected(at: url)
        }

        if let weakLevels = self.levels {
            Task { @MainActor in weakLevels.reset() }
        }

        // Spin up record-then-transcribe. The continuation is the only
        // path RecognitionUpdates flow back to the caller — emit the
        // final transcript here, then finish the stream.
        let runtimeRef = runtime
        let cont = continuation
        transcribeTask = Task {
            guard let url, let cont else {
                cont?.finish()
                return
            }
            do {
                let stream = try await runtimeRef.transcribe(audioURL: url)
                var accumulator = ""
                for try await event in stream {
                    if case .token(let token) = event {
                        accumulator += token
                    } else if case .result(let output) = event {
                        if !output.text.isEmpty {
                            accumulator = output.text
                        }
                    }
                }
                cont.yield(RecognitionUpdate(
                    text: accumulator,
                    isFinal: true,
                    timestamp: Date()
                ))
            } catch {
                cont.yield(RecognitionUpdate(
                    text: "[Granite Speech: \(error.localizedDescription)]",
                    isFinal: true,
                    timestamp: Date()
                ))
            }
            cont.finish()
        }

        recordedURL = nil
        continuation = nil
    }

    func stopImmediate() async {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        audioFile = nil
        recordedURL = nil
        continuation?.finish()
        continuation = nil
        transcribeTask?.cancel()
        transcribeTask = nil
        if let weakLevels = self.levels {
            Task { @MainActor in weakLevels.reset() }
        }
    }

    // MARK: - Tap-callback path

    private func ingestBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording else { return }
        try? audioFile?.write(from: buffer)
    }

    // MARK: - Resolver-source query (for GraniteLiveView's status line)

    /// Returns the source the model was resolved from on the most recent
    /// successful `prime()`. Nil if not primed. Read by the DevTools live
    /// view to render the resolver-status row.
    public var primedSource: GraniteSpeechModelResolver.Source? {
        get async { await runtime.primedSource }
    }

    // MARK: - Helpers (mirrored from SpeechRecognizer)

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord, mode: .measurement,
            options: [.duckOthers, .defaultToSpeaker]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private static func applyGain(_ buffer: AVAudioPCMBuffer, gain: Float) {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if let data = buffer.floatChannelData {
            for ch in 0..<channels {
                let p = data[ch]
                for i in 0..<frames {
                    p[i] *= gain
                }
            }
        } else if let data = buffer.int16ChannelData {
            for ch in 0..<channels {
                let p = data[ch]
                for i in 0..<frames {
                    let scaled = Float(p[i]) * gain
                    p[i] = Int16(max(-32767, min(32767, scaled)))
                }
            }
        }
    }

    private static func copyBuffer(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameCapacity) else {
            return nil
        }
        copy.frameLength = b.frameLength
        let frames = Int(b.frameLength)
        let channels = Int(b.format.channelCount)
        if let src = b.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Float>.size)
            }
        } else if let src = b.int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Int16>.size)
            }
        }
        return copy
    }

    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength {
            let s = samples[i]
            sum += s * s
        }
        return sqrtf(sum / Float(frameLength))
    }
}
