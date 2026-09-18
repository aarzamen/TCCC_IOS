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
    private var inputProcessor = MicrophoneInputProcessor()

    private let engine = AVAudioEngine()
    private var writer: PCMArchiveWriter?
    private var audioCapture: GraniteAudioCapture?
    private var captureID: UUID?
    /// Recognition can be invalidated immediately; admitted archive writes
    /// retain their authority until the capture consumer has drained.
    private var writerGeneration: UUID?
    private var requestID = UUID()
    private var isStarting = false
    private var isFinishing = false
    private var recordedURL: URL?
    private var continuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var isPrimed: Bool = false
    private var isRecording: Bool = false
    private var transcribeTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?

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
        levels: AudioLevels? = nil
    ) {
        self.runtime = runtime
        self.levels = levels
    }

    // MARK: - TranscriptStream

    func authorize() async throws {
        // Mic permission first — needed regardless of model state.
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { @Sendable granted in cont.resume(returning: granted) }
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
        await stopImmediate()
        if isPrimed {
            await runtime.unload()
            isPrimed = false
        }
    }

    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> {
        guard !isStarting, !isRecording, !isFinishing else { throw TranscriptStreamError.alreadyRunning }
        isStarting = true
        defer { isStarting = false }
        let generation = UUID()
        captureID = generation
        requestID = UUID()
        if !isPrimed { try await prime() }
        guard captureID == generation, !Task.isCancelled else { throw CancellationError() }

        try configureSession()

        let inputNode = engine.inputNode

        inputProcessor = .configured(for: inputNode)

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            throw TranscriptStreamError.engineFailed("Microphone audio format is unavailable")
        }
        let url = audioURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("granite-live-\(UUID().uuidString).m4a")
        // Failure to create the protected archive must stop capture. Never fall
        // back to an unprotected file or decode an empty recording as success.
        do {
            try ProtectedWrite.createEmpty(at: url)
            let file = try AVAudioFile(forWriting: url,
                settings: AudioCaptureConfig.aacOutputSettings,
                commonFormat: .pcmFormatFloat32, interleaved: false)
            writer = try PCMArchiveWriter(inputFormat: format, audioFile: file)
            writerGeneration = generation
            recordedURL = url
        } catch {
            throw TranscriptStreamError.engineFailed("Audio recording could not start: \(error.localizedDescription)")
        }

        let capture = GraniteAudioCapture(maxQueuedFrames: Int(format.sampleRate * 5)) { [weak self] buffer in
            guard let self else { throw CancellationError() }
            try await self.ingestBuffer(buffer, generation: generation)
        }
        audioCapture = capture
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let capturedAt = ProcessInfo.processInfo.systemUptime
                - Double(buffer.frameLength) / buffer.format.sampleRate
            guard let copy = Self.copyBuffer(buffer) else {
                capture.fail("Could not copy microphone audio; recording is incomplete")
                return
            }
            capture.enqueue(copy, capturedAt: capturedAt)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            capture.closeAdmission()
            _ = await capture.closeAndDrain()
            audioCapture = nil
            writer = nil
            writerGeneration = nil
            recordedURL = nil
            throw TranscriptStreamError.engineFailed(error.localizedDescription)
        }
        isRecording = true

        let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() async {
        guard isRecording, let generation = captureID, let capture = audioCapture else { return }
        isRecording = false
        isFinishing = true
        // No task-per-buffer: close admission first, then wait for its one
        // consumer before releasing the file and starting model inference.
        capture.closeAdmission()
        stopMicrophone()
        let outcome = await capture.closeAndDrain()
        guard captureID == generation else { return }
        audioCapture = nil
        writer = nil
        writerGeneration = nil
        let url = recordedURL
        recordedURL = nil
        let cont = continuation
        continuation = nil
        let request = requestID
        var captureIssue = outcome.issue
        if let url {
            do { try ProtectedWrite.markProtected(at: url) }
            catch { captureIssue = "Audio protection failed: \(error.localizedDescription)" }
        }
        guard let url, let cont, let startedAt = outcome.requestStartedAt, captureIssue == nil else {
            cont?.yield(RecognitionUpdate(text: "", isFinal: true, timestamp: Date(),
                captureID: generation, requestID: request, termination: .failed,
                issue: captureIssue ?? "No microphone audio was captured", audioUnavailable: true,
                requestStartedAt: outcome.requestStartedAt))
            cont?.finish()
            isFinishing = false
            return
        }

        let runtimeRef = runtime
        transcribeTask = Task {
            var accumulator = ""
            do {
                let stream = try await runtimeRef.transcribe(audioURL: url)
                for try await event in stream {
                    try Task.checkCancellation()
                    if case .token(let token) = event {
                        accumulator += token
                    } else if case .result(let output) = event, !output.text.isEmpty {
                        accumulator = output.text
                    }
                }
                try Task.checkCancellation()
                cont.yield(RecognitionUpdate(text: accumulator, isFinal: true, timestamp: Date(),
                    captureID: generation, requestID: request, termination: .finalized,
                    requestStartedAt: startedAt))
            } catch is CancellationError {
                cont.yield(RecognitionUpdate(text: accumulator, isFinal: true, timestamp: Date(),
                    captureID: generation, requestID: request, termination: .cancelled,
                    issue: "Granite transcription was cancelled", requestStartedAt: startedAt))
            } catch {
                cont.yield(RecognitionUpdate(text: accumulator, isFinal: true, timestamp: Date(),
                    captureID: generation, requestID: request, termination: .failed,
                    issue: "Granite Speech: \(error.localizedDescription)", requestStartedAt: startedAt))
            }
            cont.finish()
            if captureID == generation {
                isFinishing = false
                transcribeTask = nil
            }
        }
    }

    func stopImmediate() async {
        if let teardownTask { await teardownTask.value; return }
        let generation = captureID
        captureID = nil // invalidates a start or normal stop suspended at an await
        isFinishing = true
        let task = transcribeTask
        task?.cancel()
        let capture = audioCapture
        capture?.closeAdmission()
        if isRecording { stopMicrophone() }
        isRecording = false
        let teardown = Task {
            let outcome = await capture?.closeAndDrain()
            audioCapture = nil
            writer = nil
            writerGeneration = nil
            recordedURL = nil
            continuation?.yield(RecognitionUpdate(text: "", isFinal: true, timestamp: Date(),
                captureID: generation, requestID: requestID, termination: .cancelled,
                issue: "Granite capture was cancelled", requestStartedAt: outcome?.requestStartedAt))
            continuation?.finish()
            continuation = nil
            if let task { await task.value }
            transcribeTask = nil
            teardownTask = nil
            isFinishing = false
        }
        teardownTask = teardown
        await teardown.value
    }

    private func stopMicrophone() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let levels { Task { @MainActor in levels.reset() } }
    }

    // MARK: - Ordered capture-consumer path

    private func ingestBuffer(_ captured: GraniteAudioCapture.PCM, generation: UUID) throws {
        guard generation == writerGeneration, let writer else { throw CancellationError() }
        try writer.append(captured.buffer) { converted in
            let report = inputProcessor.process(converted)
            if report.shouldPublish, let levels { Task { @MainActor in levels.ingest(report) } }
        }
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

    private static func copyBuffer(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameCapacity) else {
            return nil
        }
        copy.frameLength = b.frameLength
        let source = UnsafeMutableAudioBufferListPointer(b.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        for index in source.indices {
            guard let src = source[index].mData, let dst = destination[index].mData,
                  source[index].mDataByteSize <= destination[index].mDataByteSize else { return nil }
            memcpy(dst, src, Int(source[index].mDataByteSize))
        }
        return copy
    }

}
