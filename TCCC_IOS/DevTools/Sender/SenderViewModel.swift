import Foundation
@preconcurrency import AVFAudio
import Observation

struct SenderVoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

struct SenderSynthesisRequest: Sendable, Equatable {
    let text: String
    let voiceID: String
    let speed: Double
    let pitchSemitones: Double
    let volume: Double
}

struct SenderSentenceTiming: Sendable, Equatable, Identifiable {
    let id: UUID
    let range: Range<String.Index>?
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(
        id: UUID = UUID(),
        range: Range<String.Index>? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.range = range
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct SenderSynthesisResult: Sendable, Equatable {
    let audioURL: URL
    let duration: TimeInterval
    let sentenceTimings: [SenderSentenceTiming]
    let rendererName: String
}

enum SenderSynthesisState: Equatable, Sendable {
    case idle
    case synthesizing
    case ready
    case failed(String)
}

struct SenderReadoutState: Identifiable, Sendable, Equatable {
    let id: UUID
    let script: String
    let voiceID: String
    let speed: Double
    let pitchSemitones: Double
    let volume: Double
    let estimatedDuration: TimeInterval
    let synthesisResult: SenderSynthesisResult?
    let errorMessage: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        script: String,
        voiceID: String,
        speed: Double,
        pitchSemitones: Double,
        volume: Double,
        estimatedDuration: TimeInterval,
        synthesisResult: SenderSynthesisResult?,
        errorMessage: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.script = script
        self.voiceID = voiceID
        self.speed = speed
        self.pitchSemitones = pitchSemitones
        self.volume = volume
        self.estimatedDuration = estimatedDuration
        self.synthesisResult = synthesisResult
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

enum SenderSynthesisError: LocalizedError, Sendable, Equatable {
    case emptyScript

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            "Paste a scenario script before sending."
        }
    }
}

@MainActor
@Observable
final class SenderViewModel {
    typealias SynthesisHandler = @Sendable (SenderSynthesisRequest) async throws -> SenderSynthesisResult

    static let readingWordsPerMinute = 150

    var script: String = ""
    var selectedVoiceID: String = KokoroEngine.defaultVoiceID
    var speed: Double = 1.0 {
        didSet { speed = Self.clamp(speed, to: 0.7...1.3) }
    }
    var pitchSemitones: Double = 0 {
        didSet { pitchSemitones = Self.clamp(pitchSemitones, to: -2...2) }
    }
    var volume: Double = 0.8 {
        didSet {
            volume = Self.clamp(volume, to: 0...1)
            audioPlayer?.volume = Float(volume)
        }
    }

    private(set) var isSending: Bool = false
    private(set) var synthesisState: SenderSynthesisState = .idle
    private(set) var readout: SenderReadoutState?
    private(set) var errorMessage: String?
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var levelSamples: [Double] = Array(repeating: 0, count: 48)

    @ObservationIgnored private let synthesizeHandler: SynthesisHandler
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var playbackTimer: Timer?

    init(synthesizeHandler: @escaping SynthesisHandler = SenderViewModel.deviceTTSHandler) {
        self.synthesizeHandler = synthesizeHandler
    }

    var availableVoices: [SenderVoiceOption] {
        KokoroEngine.voices.map { voice in
            SenderVoiceOption(id: voice.id, displayName: voice.displayName)
        }
    }

    var trimmedScript: String {
        script.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSend: Bool {
        !trimmedScript.isEmpty && !isSending
    }

    var wordCount: Int {
        trimmedScript.split(whereSeparator: \.isWhitespace).count
    }

    var estimatedReadingMinutes: Double {
        Double(max(wordCount, 1)) / Double(Self.readingWordsPerMinute)
    }

    var estimatedDuration: TimeInterval {
        estimatedReadingMinutes * 60
    }

    var estimatedReadingTimeLabel: String {
        if estimatedReadingMinutes < 1 {
            return "<1 min"
        }
        let minutes = Int(ceil(estimatedReadingMinutes))
        return "\(minutes) min"
    }

    var selectedVoiceDisplayName: String {
        availableVoices.first(where: { $0.id == selectedVoiceID })?.displayName ?? selectedVoiceID
    }

    var duration: TimeInterval {
        readout?.synthesisResult?.duration ?? audioPlayer?.duration ?? 0
    }

    var activeSentenceIndex: Int? {
        guard
            isPlaying,
            let timings = readout?.synthesisResult?.sentenceTimings,
            !timings.isEmpty
        else {
            return nil
        }

        return timings.firstIndex { timing in
            currentTime >= timing.startTime && currentTime <= timing.endTime
        }
    }

    func setSpeed(_ newValue: Double) {
        speed = Self.clamp(newValue, to: 0.7...1.3)
    }

    func setPitchSemitones(_ newValue: Double) {
        pitchSemitones = Self.clamp(newValue, to: -2...2)
    }

    func setVolume(_ newValue: Double) {
        volume = Self.clamp(newValue, to: 0...1)
    }

    @discardableResult
    func send() async -> SenderReadoutState? {
        let text = trimmedScript
        guard !text.isEmpty else {
            errorMessage = SenderSynthesisError.emptyScript.errorDescription
            return nil
        }

        isSending = true
        synthesisState = .synthesizing
        errorMessage = nil
        stopPlayback()
        defer { isSending = false }

        let request = SenderSynthesisRequest(
            text: text,
            voiceID: selectedVoiceID,
            speed: speed,
            pitchSemitones: pitchSemitones,
            volume: volume
        )

        do {
            let result = try await synthesizeHandler(request)
            let state = makeReadout(script: text, result: result, errorMessage: nil)
            readout = state
            if prepareAudioPlayer(with: result) {
                synthesisState = .ready
            }
            return state
        } catch {
            let message = Self.message(for: error)
            errorMessage = message
            let state = makeReadout(script: text, result: nil, errorMessage: message)
            readout = state
            audioPlayer = nil
            levelSamples = Array(repeating: 0, count: 48)
            currentTime = 0
            synthesisState = .failed(message)
            return state
        }
    }

    func returnToCompose() {
        stopPlayback()
        readout = nil
        errorMessage = nil
        synthesisState = .idle
    }

    func play() {
        guard let audioPlayer, duration > 0 else { return }
        audioPlayer.volume = Float(volume)
        audioPlayer.isMeteringEnabled = true
        audioPlayer.play()
        isPlaying = true
        startPlaybackTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopPlaybackTimer()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        levelSamples = Array(repeating: 0, count: 48)
        stopPlaybackTimer()
    }

    func seek(to fraction: Double) {
        let clamped = Self.clamp(fraction, to: 0...1)
        let targetTime = duration * clamped
        audioPlayer?.currentTime = targetTime
        currentTime = targetTime
        samplePlaybackLevels()
    }

    func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }
        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func makeReadout(
        script: String,
        result: SenderSynthesisResult?,
        errorMessage: String?
    ) -> SenderReadoutState {
        SenderReadoutState(
            script: script,
            voiceID: selectedVoiceID,
            speed: speed,
            pitchSemitones: pitchSemitones,
            volume: volume,
            estimatedDuration: result?.duration ?? estimatedDuration,
            synthesisResult: result,
            errorMessage: errorMessage
        )
    }

    private func prepareAudioPlayer(with result: SenderSynthesisResult) -> Bool {
        do {
            let player = try AVAudioPlayer(contentsOf: result.audioURL)
            player.isMeteringEnabled = true
            player.volume = Float(volume)
            audioPlayer = player
            currentTime = 0
            levelSamples = Array(repeating: 0, count: 48)
            return true
        } catch {
            audioPlayer = nil
            synthesisState = .failed("Audio was generated but could not be opened: \(error.localizedDescription)")
            return false
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickPlayback()
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func tickPlayback() {
        guard let audioPlayer else {
            stopPlayback()
            return
        }

        currentTime = audioPlayer.currentTime
        samplePlaybackLevels()

        if !audioPlayer.isPlaying {
            isPlaying = false
            stopPlaybackTimer()
            if duration > 0, currentTime >= duration - 0.05 {
                currentTime = duration
            }
        }
    }

    private func samplePlaybackLevels() {
        guard let audioPlayer, audioPlayer.isMeteringEnabled else {
            levelSamples = Array(repeating: 0, count: 48)
            return
        }

        audioPlayer.updateMeters()
        let average = Self.normalizedPower(audioPlayer.averagePower(forChannel: 0))
        let peak = Self.normalizedPower(audioPlayer.peakPower(forChannel: 0))
        let sample = max(average, peak * 0.65)
        levelSamples.append(sample)
        if levelSamples.count > 48 {
            levelSamples.removeFirst(levelSamples.count - 48)
        }
    }

    private static let deviceTTSHandler: SynthesisHandler = { request in
        let result = try await KokoroEngine().synthesize(
            KokoroSynthesisRequest(
                text: request.text,
                voiceID: request.voiceID,
                speed: request.speed,
                pitchSemitones: request.pitchSemitones
            )
        )
        return SenderSynthesisResult(kokoroResult: result)
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func normalizedPower(_ dBFS: Float) -> Double {
        let clamped = min(max(Double(dBFS), -80), 0)
        return (clamped + 80) / 80
    }
}

private extension SenderSynthesisResult {
    init(kokoroResult: KokoroSynthesisResult) {
        self.audioURL = kokoroResult.audioURL
        self.duration = kokoroResult.duration
        self.rendererName = kokoroResult.rendererName
        self.sentenceTimings = kokoroResult.sentenceTimings.map { timing in
            SenderSentenceTiming(
                startTime: timing.startTime,
                endTime: timing.endTime
            )
        }
    }
}
