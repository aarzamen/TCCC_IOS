import Foundation
@preconcurrency import AVFAudio
@preconcurrency import AVFoundation
@preconcurrency import CoreML
@preconcurrency import FluidAudio

struct KokoroVoice: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let locale: String
    let grade: String?
    let checksumPrefix: String?

    init(
        id: String,
        displayName: String? = nil,
        locale: String,
        grade: String? = nil,
        checksumPrefix: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? "\(id) - \(locale)"
        self.locale = locale
        self.grade = grade
        self.checksumPrefix = checksumPrefix
    }
}

struct KokoroSentenceTiming: Identifiable, Hashable, Sendable {
    let id = UUID()
    let sentence: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct KokoroSynthesisRequest: Sendable {
    let text: String
    let voiceID: String
    let speed: Double
    let pitchSemitones: Double
}

struct KokoroSynthesisResult: Sendable {
    let audioURL: URL
    let duration: TimeInterval
    let sentenceTimings: [KokoroSentenceTiming]
    let rendererName: String
}

struct KokoroNativeSynthesisRequest: Sendable {
    let text: String
    let voiceID: String
    let speed: Double
    let pitchSemitones: Double
}

struct KokoroNativeSynthesisResult: Sendable {
    let audioData: Data
    let rendererName: String
}

protocol KokoroNativeSynthesizing: Sendable {
    func synthesize(_ request: KokoroNativeSynthesisRequest) async throws -> KokoroNativeSynthesisResult
}

enum KokoroEngineError: LocalizedError, Equatable, Sendable {
    case emptyScript
    case unsupportedVoice(String)
    case invalidSpeed(Double)
    case invalidPitchSemitones(Double)
    case synthesisFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            return "Paste a scenario script before playback."
        case .unsupportedVoice(let voice):
            return "TTS voice '\(voice)' is not in the local voice catalog."
        case .invalidSpeed(let speed):
            return "TTS speed \(speed) is outside the supported 0.5...2.0 range."
        case .invalidPitchSemitones(let pitch):
            return "TTS pitch \(pitch) is outside the supported -12...12 semitone range."
        case .synthesisFailed(let message):
            return "TTS synthesis failed: \(message)"
        }
    }
}

struct KokoroEngine: Sendable {
    static let defaultVoiceID = "af_heart"
    private let nativeSynthesizer: any KokoroNativeSynthesizing

    init(nativeSynthesizer: any KokoroNativeSynthesizing = CascadingNativeSynthesizer()) {
        self.nativeSynthesizer = nativeSynthesizer
    }

    // Voice IDs are Kokoro-compatible. The preferred renderer is FluidAudio's
    // CoreML Kokoro path; iOS speech is kept as a fallback so the sender button
    // still produces real audio if model assets are missing or downloading.
    static let voices: [KokoroVoice] = [
        KokoroVoice(id: "af_heart", locale: "American English", grade: "A", checksumPrefix: "0ab5709b"),
        KokoroVoice(id: "af_alloy", locale: "American English", grade: "C", checksumPrefix: "6d877149"),
        KokoroVoice(id: "af_aoede", locale: "American English", grade: "C+", checksumPrefix: "c03bd1a4"),
        KokoroVoice(id: "af_bella", locale: "American English", grade: "A-", checksumPrefix: "8cb64e02"),
        KokoroVoice(id: "af_jessica", locale: "American English", grade: "D", checksumPrefix: "cdfdccb8"),
        KokoroVoice(id: "af_kore", locale: "American English", grade: "C+", checksumPrefix: "8bfbc512"),
        KokoroVoice(id: "af_nicole", locale: "American English", grade: "B-", checksumPrefix: "c5561808"),
        KokoroVoice(id: "af_nova", locale: "American English", grade: "C", checksumPrefix: "e0233676"),
        KokoroVoice(id: "af_river", locale: "American English", grade: "D", checksumPrefix: "e149459b"),
        KokoroVoice(id: "af_sarah", locale: "American English", grade: "C+", checksumPrefix: "49bd364e"),
        KokoroVoice(id: "af_sky", locale: "American English", grade: "C-", checksumPrefix: "c799548a"),
        KokoroVoice(id: "am_adam", locale: "American English", grade: "F+", checksumPrefix: "ced7e284"),
        KokoroVoice(id: "am_echo", locale: "American English", grade: "D", checksumPrefix: "8bcfdc85"),
        KokoroVoice(id: "am_eric", locale: "American English", grade: "D", checksumPrefix: "ada66f0e"),
        KokoroVoice(id: "am_fenrir", locale: "American English", grade: "C+", checksumPrefix: "98e507ec"),
        KokoroVoice(id: "am_liam", locale: "American English", grade: "D", checksumPrefix: "c8255075"),
        KokoroVoice(id: "am_michael", locale: "American English", grade: "C+", checksumPrefix: "9a443b79"),
        KokoroVoice(id: "am_onyx", locale: "American English", grade: "D", checksumPrefix: "e8452be1"),
        KokoroVoice(id: "am_puck", locale: "American English", grade: "C+", checksumPrefix: "dd1d8973"),
        KokoroVoice(id: "am_santa", locale: "American English", grade: "D-", checksumPrefix: "7f2f7582"),
        KokoroVoice(id: "bf_alice", locale: "British English", grade: "D", checksumPrefix: "d292651b"),
        KokoroVoice(id: "bf_emma", locale: "British English", grade: "B-", checksumPrefix: "d0a423de"),
        KokoroVoice(id: "bf_isabella", locale: "British English", grade: "C", checksumPrefix: "cdd4c370"),
        KokoroVoice(id: "bf_lily", locale: "British English", grade: "D", checksumPrefix: "6e09c2e4"),
        KokoroVoice(id: "bm_daniel", locale: "British English", grade: "D", checksumPrefix: "fc3fce4e"),
        KokoroVoice(id: "bm_fable", locale: "British English", grade: "C", checksumPrefix: "d44935f3"),
        KokoroVoice(id: "bm_george", locale: "British English", grade: "C", checksumPrefix: "f1bc8122"),
        KokoroVoice(id: "bm_lewis", locale: "British English", grade: "D+", checksumPrefix: "b5204750"),
        KokoroVoice(id: "jf_alpha", locale: "Japanese", grade: "C+", checksumPrefix: "1bf4c9dc"),
        KokoroVoice(id: "jf_gongitsune", locale: "Japanese", grade: "C", checksumPrefix: "1b171917"),
        KokoroVoice(id: "jf_nezumi", locale: "Japanese", grade: "C-", checksumPrefix: "d83f007a"),
        KokoroVoice(id: "jf_tebukuro", locale: "Japanese", grade: "C", checksumPrefix: "0d691790"),
        KokoroVoice(id: "jm_kumo", locale: "Japanese", grade: "C-", checksumPrefix: "98340afd"),
        KokoroVoice(id: "zf_xiaobei", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "9b76be63"),
        KokoroVoice(id: "zf_xiaoni", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "95b49f16"),
        KokoroVoice(id: "zf_xiaoxiao", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "cfaf6f2d"),
        KokoroVoice(id: "zf_xiaoyi", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "b5235dba"),
        KokoroVoice(id: "zm_yunjian", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "76cbf8ba"),
        KokoroVoice(id: "zm_yunxi", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "dbe6e1ce"),
        KokoroVoice(id: "zm_yunxia", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "bb2b03b0"),
        KokoroVoice(id: "zm_yunyang", locale: "Mandarin Chinese", grade: "D", checksumPrefix: "5238ac22"),
        KokoroVoice(id: "ef_dora", locale: "Spanish", checksumPrefix: "d9d69b0f"),
        KokoroVoice(id: "em_alex", locale: "Spanish", checksumPrefix: "5eac53f7"),
        KokoroVoice(id: "em_santa", locale: "Spanish", checksumPrefix: "aa8620cb"),
        KokoroVoice(id: "ff_siwis", locale: "French", grade: "B-", checksumPrefix: "8073bf2d"),
        KokoroVoice(id: "hf_alpha", locale: "Hindi", grade: "C", checksumPrefix: "06906fe0"),
        KokoroVoice(id: "hf_beta", locale: "Hindi", grade: "C", checksumPrefix: "63c0a1a6"),
        KokoroVoice(id: "hm_omega", locale: "Hindi", grade: "C", checksumPrefix: "b55f02a8"),
        KokoroVoice(id: "hm_psi", locale: "Hindi", grade: "C", checksumPrefix: "2f0f055c"),
        KokoroVoice(id: "if_sara", locale: "Italian", grade: "C", checksumPrefix: "6c0b253b"),
        KokoroVoice(id: "im_nicola", locale: "Italian", grade: "C", checksumPrefix: "234ed066"),
        KokoroVoice(id: "pf_dora", locale: "Brazilian Portuguese", checksumPrefix: "07e4ff98"),
        KokoroVoice(id: "pm_alex", locale: "Brazilian Portuguese", checksumPrefix: "cf0ba8c5"),
        KokoroVoice(id: "pm_santa", locale: "Brazilian Portuguese", checksumPrefix: "d4210316")
    ]

    var availableVoices: [KokoroVoice] {
        Self.voices
    }

    func synthesize(_ request: KokoroSynthesisRequest) async throws -> KokoroSynthesisResult {
        try await synthesize(
            text: request.text,
            voice: request.voiceID,
            speed: request.speed,
            pitchSemitones: request.pitchSemitones
        )
    }

    func synthesize(
        text: String,
        voice voiceID: String = Self.defaultVoiceID,
        speed: Double = 1.0,
        pitchSemitones: Double = 0.0
    ) async throws -> KokoroSynthesisResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KokoroEngineError.emptyScript }
        guard Self.voices.contains(where: { $0.id == voiceID }) else {
            throw KokoroEngineError.unsupportedVoice(voiceID)
        }
        guard (0.5...2.0).contains(speed) else {
            throw KokoroEngineError.invalidSpeed(speed)
        }
        guard (-12.0...12.0).contains(pitchSemitones) else {
            throw KokoroEngineError.invalidPitchSemitones(pitchSemitones)
        }

        let nativeResult = try await nativeSynthesizer.synthesize(
            KokoroNativeSynthesisRequest(
                text: trimmed,
                voiceID: voiceID,
                speed: speed,
                pitchSemitones: pitchSemitones
            )
        )
        guard !nativeResult.audioData.isEmpty else {
            throw KokoroEngineError.synthesisFailed("Renderer returned no audio.")
        }

        let outputURL = try Self.makeOutputURL()
        try nativeResult.audioData.write(to: outputURL, options: [.atomic])
        let duration = try Self.duration(ofAudioAt: outputURL)

        return KokoroSynthesisResult(
            audioURL: outputURL,
            duration: duration,
            sentenceTimings: Self.sentenceTimings(for: trimmed, duration: duration),
            rendererName: nativeResult.rendererName
        )
    }

    private static func makeOutputURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tccc-devtools-tts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tts-\(UUID().uuidString).wav")
    }

    private static func duration(ofAudioAt url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else {
            throw KokoroEngineError.synthesisFailed("Generated audio has an invalid sample rate.")
        }
        return Double(file.length) / sampleRate
    }

    private static func sentenceTimings(for text: String, duration: TimeInterval) -> [KokoroSentenceTiming] {
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else { return [] }

        let weights = sentences.map { max(1, $0.split(whereSeparator: \.isWhitespace).count) }
        let totalWeight = max(1, weights.reduce(0, +))
        var cursor: TimeInterval = 0

        return sentences.enumerated().map { index, sentence in
            let start = cursor
            let end: TimeInterval
            if index == sentences.indices.last {
                end = duration
            } else {
                end = min(duration, cursor + (duration * Double(weights[index]) / Double(totalWeight)))
            }
            cursor = end
            return KokoroSentenceTiming(sentence: sentence, startTime: start, endTime: end)
        }
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var start = text.startIndex
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "." || character == "!" || character == "?" || character == "\n" {
                let end = text.index(after: cursor)
                appendSentence(text[start..<end], to: &sentences)
                start = end
                while start < text.endIndex && text[start].isWhitespace {
                    start = text.index(after: start)
                }
                cursor = start
            } else {
                cursor = text.index(after: cursor)
            }
        }

        if start < text.endIndex {
            appendSentence(text[start..<text.endIndex], to: &sentences)
        }

        return sentences
    }

    private static func appendSentence(_ slice: Substring, to sentences: inout [String]) {
        let sentence = String(slice).trimmingCharacters(in: .whitespacesAndNewlines)
        if !sentence.isEmpty {
            sentences.append(sentence)
        }
    }
}

struct CascadingNativeSynthesizer: KokoroNativeSynthesizing {
    private let primary: any KokoroNativeSynthesizing
    private let fallback: any KokoroNativeSynthesizing

    init(
        primary: any KokoroNativeSynthesizing = FluidAudioKokoroNativeSynthesizer(),
        fallback: any KokoroNativeSynthesizing = AppleSpeechNativeSynthesizer()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func synthesize(_ request: KokoroNativeSynthesisRequest) async throws -> KokoroNativeSynthesisResult {
        do {
            return try await primary.synthesize(request)
        } catch {
            return try await fallback.synthesize(request)
        }
    }
}

actor FluidAudioKokoroNativeSynthesizer: KokoroNativeSynthesizing {
    private var manager: KokoroTtsManager?
    private var isSynthesizing = false

    func synthesize(_ request: KokoroNativeSynthesisRequest) async throws -> KokoroNativeSynthesisResult {
        guard !isSynthesizing else {
            throw KokoroEngineError.synthesisFailed("Kokoro renderer is already synthesizing.")
        }
        isSynthesizing = true
        defer { isSynthesizing = false }

        let manager = try await managerForCurrentProcess()
        let voice = Self.supportedFluidVoice(for: request.voiceID)
        let audioData = try await manager.synthesize(
            text: request.text,
            voice: voice,
            voiceSpeed: Float(request.speed),
            variantPreference: .fifteenSecond
        )
        return KokoroNativeSynthesisResult(audioData: audioData, rendererName: "Kokoro CoreML")
    }

    private func managerForCurrentProcess() async throws -> KokoroTtsManager {
        if let manager {
            return manager
        }

        let manager = KokoroTtsManager(
            defaultVoice: TtsConstants.recommendedVoice,
            computeUnits: .cpuAndGPU
        )
        try await manager.initialize(preloadVoices: [TtsConstants.recommendedVoice])
        self.manager = manager
        return manager
    }

    private static func supportedFluidVoice(for voiceID: String) -> String {
        // FluidAudio's Kokoro path is beta-tested for American English. Other
        // Kokoro IDs remain in the app picker for compatibility, but the
        // CoreML renderer falls back to af_heart when the selected voice is
        // outside that tested American narrator set.
        guard TtsConstants.availableVoices.contains(voiceID) else {
            return TtsConstants.recommendedVoice
        }
        guard voiceID.hasPrefix("af_") || voiceID.hasPrefix("am_") else {
            return TtsConstants.recommendedVoice
        }
        return voiceID
    }
}

struct AppleSpeechNativeSynthesizer: KokoroNativeSynthesizing {
    func synthesize(_ request: KokoroNativeSynthesisRequest) async throws -> KokoroNativeSynthesisResult {
        let audioData = try await AppleSpeechRenderSession.render(request)
        return KokoroNativeSynthesisResult(audioData: audioData, rendererName: "Device Speech")
    }
}

@MainActor
private final class AppleSpeechRenderSession {
    static func render(_ request: KokoroNativeSynthesisRequest) async throws -> Data {
        try await AppleSpeechRenderSession().render(request)
    }

    private func render(_ request: KokoroNativeSynthesisRequest) async throws -> Data {
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = Self.voice(for: request.voiceID)
        utterance.rate = Self.speechRate(for: request.speed)
        utterance.pitchMultiplier = Self.pitchMultiplier(for: request.pitchSemitones)
        utterance.volume = 1

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-render-\(UUID().uuidString).wav")
        try await render(utterance, to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        return try Data(contentsOf: outputURL)
    }

    private func render(_ utterance: AVSpeechUtterance, to outputURL: URL) async throws {
        let synthesizer = AVSpeechSynthesizer()
        let callbackBox = AppleSpeechRenderCallbackBox(outputURL: outputURL, synthesizer: synthesizer)

        try await withCheckedThrowingContinuation { continuation in
            callbackBox.setContinuation(continuation)
            synthesizer.write(utterance) { buffer in
                callbackBox.handle(buffer)
            }
        }
    }

    private static func voice(for voiceID: String) -> AVSpeechSynthesisVoice? {
        let language = languageCode(for: voiceID)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return voices.first(where: { $0.language == language })
            ?? AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func languageCode(for voiceID: String) -> String {
        if voiceID.hasPrefix("bf_") || voiceID.hasPrefix("bm_") { return "en-GB" }
        if voiceID.hasPrefix("ef_") || voiceID.hasPrefix("em_") { return "es-US" }
        if voiceID.hasPrefix("ff_") { return "fr-FR" }
        if voiceID.hasPrefix("hf_") || voiceID.hasPrefix("hm_") { return "hi-IN" }
        if voiceID.hasPrefix("if_") || voiceID.hasPrefix("im_") { return "it-IT" }
        if voiceID.hasPrefix("jf_") || voiceID.hasPrefix("jm_") { return "ja-JP" }
        if voiceID.hasPrefix("pf_") || voiceID.hasPrefix("pm_") { return "pt-BR" }
        if voiceID.hasPrefix("zf_") || voiceID.hasPrefix("zm_") { return "zh-CN" }
        return "en-US"
    }

    private static func speechRate(for speed: Double) -> Float {
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
    }

    private static func pitchMultiplier(for semitones: Double) -> Float {
        let multiplier = pow(2.0, semitones / 12.0)
        return Float(min(2.0, max(0.5, multiplier)))
    }
}

private final class AppleSpeechRenderCallbackBox: @unchecked Sendable {
    private let outputURL: URL
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var continuation: CheckedContinuation<Void, Error>?
    private var synthesizer: AVSpeechSynthesizer?

    init(outputURL: URL, synthesizer: AVSpeechSynthesizer) {
        self.outputURL = outputURL
        self.synthesizer = synthesizer
    }

    func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func handle(_ buffer: AVAudioBuffer) {
        var continuationToResume: CheckedContinuation<Void, Error>?
        var result: Result<Void, Error>?

        lock.lock()
        if continuation == nil {
            lock.unlock()
            return
        }

        do {
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                continuationToResume = finishLocked()
                result = .failure(KokoroEngineError.synthesisFailed("Speech renderer returned a non-PCM buffer."))
                lock.unlock()
                resume(continuationToResume, with: result)
                return
            }

            if pcmBuffer.frameLength == 0 {
                continuationToResume = finishLocked()
                result = .success(())
                lock.unlock()
                resume(continuationToResume, with: result)
                return
            }

            if audioFile == nil {
                audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
            }
            try audioFile?.write(from: pcmBuffer)
            lock.unlock()
        } catch {
            continuationToResume = finishLocked()
            result = .failure(error)
            lock.unlock()
            resume(continuationToResume, with: result)
        }
    }

    private func finishLocked() -> CheckedContinuation<Void, Error>? {
        let next = continuation
        continuation = nil
        audioFile = nil
        synthesizer = nil
        return next
    }

    private func resume(_ continuation: CheckedContinuation<Void, Error>?, with result: Result<Void, Error>?) {
        guard let continuation, let result else { return }
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
