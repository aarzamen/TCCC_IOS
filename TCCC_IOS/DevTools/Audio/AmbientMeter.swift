import Foundation
import Observation
import os
@preconcurrency import AVFAudio

@MainActor
@Observable
final class AmbientMeter {
    private(set) var isSampling: Bool = false
    private(set) var isStarting: Bool = false
    private(set) var dBFS: Double = AmbientMeterMath.minimumDBFS
    private(set) var normalizedLevel: Double = 0
    private(set) var statusMessage: String = "Ambient mic idle"

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var ownsSession = false
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var samplePump = AmbientMeterSamplePump()

    func start() async {
        guard !isSampling, !isStarting else { return }
        let token = UUID()
        runID = token
        isStarting = true
        statusMessage = "Requesting microphone access…"
        defer { if runID == token { isStarting = false } }

        let granted = await requestMicrophonePermission()
        guard runID == token, !Task.isCancelled else { return }
        guard granted else {
            statusMessage = "Microphone permission denied"
            dBFS = AmbientMeterMath.minimumDBFS
            normalizedLevel = 0
            return
        }

        do {
            try configureSession()
            try installTapAndStartEngine()
            isSampling = true
            statusMessage = "Sampling ambient level · audio is not saved"
        } catch {
            stop()
            statusMessage = "Ambient meter unavailable: \(error.localizedDescription)"
        }
    }

    func stop() {
        runID = UUID()
        isStarting = false
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if ownsSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsSession = false
        }
        samplePump.reset()
        isSampling = false
        dBFS = AmbientMeterMath.minimumDBFS
        normalizedLevel = 0
        statusMessage = "Ambient metering paused"
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.duckOthers, .defaultToSpeaker]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        ownsSession = true
    }

    private func installTapAndStartEngine() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AmbientMeterError.inputFormatUnavailable
        }

        let token = runID
        // Create the audio callback outside MainActor isolation. AVAudioEngine
        // invokes it on its render queue; only value samples cross to the UI.
        let tap = Self.makeTap(pump: samplePump) { [weak self] sample in
            Task { @MainActor [weak self] in
                guard let self, self.runID == token, self.isSampling else { return }
                self.dBFS = sample.dBFS
                self.normalizedLevel = sample.normalizedLevel
            }
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
            throw error
        }
    }
    nonisolated private static func makeTap(
        pump: AmbientMeterSamplePump,
        publish: @escaping @Sendable (AmbientMeterSample) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { @Sendable buffer, _ in
            guard let sample = pump.ingest(buffer) else { return }
            publish(sample)
        }
    }

}

private enum AmbientMeterError: LocalizedError {
    case inputFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .inputFormatUnavailable:
            "No microphone input format is available"
        }
    }
}

private struct AmbientMeterSample: Sendable {
    let dBFS: Double
    let normalizedLevel: Double
}

private enum AmbientMeterMath {
    static let minimumDBFS: Double = -90
    static let maximumDBFS: Double = 0
    static let publishInterval: TimeInterval = 0.1

    static func dBFS(fromRMS rms: Double) -> Double {
        let safeRMS = max(rms, 0.000_000_1)
        let raw = 20.0 * log10(safeRMS)
        return min(max(raw, minimumDBFS), maximumDBFS)
    }

    static func normalizedLevel(for dBFS: Double) -> Double {
        (dBFS - minimumDBFS) / (maximumDBFS - minimumDBFS)
    }
}

private final class AmbientMeterSamplePump: @unchecked Sendable {
    private struct State {
        var smoothedDBFS: Double = AmbientMeterMath.minimumDBFS
        var lastPublishTime: TimeInterval = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func ingest(_ buffer: AVAudioPCMBuffer) -> AmbientMeterSample? {
        let rawDBFS = AmbientMeterMath.dBFS(fromRMS: Self.rms(buffer))
        let now = Date.timeIntervalSinceReferenceDate

        return lock.withLock { state in
            if state.smoothedDBFS <= AmbientMeterMath.minimumDBFS + 0.01 {
                state.smoothedDBFS = rawDBFS
            } else {
                state.smoothedDBFS = (rawDBFS * 0.35) + (state.smoothedDBFS * 0.65)
            }

            guard now - state.lastPublishTime >= AmbientMeterMath.publishInterval else {
                return nil
            }
            state.lastPublishTime = now
            let smoothed = state.smoothedDBFS
            return AmbientMeterSample(
                dBFS: smoothed,
                normalizedLevel: AmbientMeterMath.normalizedLevel(for: smoothed)
            )
        }
    }

    func reset() {
        lock.withLock { state in
            state = State()
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        if let channelData = buffer.floatChannelData {
            let channels = Int(buffer.format.channelCount)
            var sum: Double = 0
            var sampleCount = 0
            for channel in 0..<channels {
                let samples = channelData[channel]
                for frame in 0..<frameLength {
                    let sample = Double(samples[frame])
                    sum += sample * sample
                }
                sampleCount += frameLength
            }
            guard sampleCount > 0 else { return 0 }
            return sqrt(sum / Double(sampleCount))
        }

        if let channelData = buffer.int16ChannelData {
            let channels = Int(buffer.format.channelCount)
            var sum: Double = 0
            var sampleCount = 0
            for channel in 0..<channels {
                let samples = channelData[channel]
                for frame in 0..<frameLength {
                    let sample = Double(samples[frame]) / 32768.0
                    sum += sample * sample
                }
                sampleCount += frameLength
            }
            guard sampleCount > 0 else { return 0 }
            return sqrt(sum / Double(sampleCount))
        }

        return 0
    }
}
