import Foundation

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
}

enum KokoroNativeRuntimeBlocker: Equatable, Sendable, CustomStringConvertible {
    case pythonPyTorchOnly
    case nativeSynthesisNotImplemented

    var description: String {
        switch self {
        case .pythonPyTorchOnly:
            return "Kokoro native runtime unavailable: /Users/ama/Kokoro-82M contains kokoro-v1_0.pth and .pt voice tensors only; no Core ML, MLX Swift, or other Swift/iOS inference runtime is bundled. Confirm a PyTorch-to-native conversion path before enabling synthesis."
        case .nativeSynthesisNotImplemented:
            return "Kokoro native runtime was marked available, but no real native synthesizer is wired. Do not use placeholder audio or platform TTS."
        }
    }
}

enum KokoroEngineError: LocalizedError, Equatable, Sendable {
    case emptyScript
    case unsupportedVoice(String)
    case invalidSpeed(Double)
    case invalidPitchSemitones(Double)
    case nativeRuntimeUnavailable(KokoroNativeRuntimeBlocker)

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            return "Paste a scenario script before playback."
        case .unsupportedVoice(let voice):
            return "Kokoro voice '\(voice)' is not in the local voice catalog."
        case .invalidSpeed(let speed):
            return "Kokoro speed \(speed) is outside the supported 0.5...2.0 range."
        case .invalidPitchSemitones(let pitch):
            return "Kokoro pitch \(pitch) is outside the supported -12...12 semitone range."
        case .nativeRuntimeUnavailable(let blocker):
            return blocker.description
        }
    }
}

struct KokoroEngine: Sendable {
    static let defaultVoiceID = "af_heart"

    // Embedded from /Users/ama/Kokoro-82M/VOICES.md and voices/*.pt.
    // No model or voice tensor is bundled by this wrapper.
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

        throw KokoroEngineError.nativeRuntimeUnavailable(.pythonPyTorchOnly)
    }
}
