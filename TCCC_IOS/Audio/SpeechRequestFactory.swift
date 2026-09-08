import Speech

/// Single source of SFSpeechRecognizer request configuration. Production
/// capture (SpeechRecognizer) and the DevTools transcription benchmark
/// build requests here, so a config change (vocabulary biasing, task
/// hints, custom LM — sprint WS-3) lands in one place and reaches every
/// request type (live-mic buffer requests and file URL requests alike).
enum SpeechRequestFactory {
    /// Apply the shared production ASR configuration to any request type.
    /// Both `SFSpeechAudioBufferRecognitionRequest` and
    /// `SFSpeechURLRecognitionRequest` inherit from `SFSpeechRecognitionRequest`,
    /// so future vocabulary biasing (`contextualStrings`, `taskHint`, custom
    /// LM — WS-3) added here reaches both the live and benchmark lanes.
    static func configure(_ request: SFSpeechRecognitionRequest) {
        request.shouldReportPartialResults = true
        // Extraction scopes negation by sentence. Preserve recognizer-supplied
        // punctuation so an unrelated "no allergies" cannot negate a full report.
        request.addsPunctuation = true
        // RF Ghost hard constraint — cloud transcription is forbidden.
        request.requiresOnDeviceRecognition = true
    }

    /// Live-mic capture request (production `SpeechRecognizer`).
    static func makeBufferRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let req = SFSpeechAudioBufferRecognitionRequest()
        configure(req)
        return req
    }

    /// File-transcription request (DevTools benchmark). Same recognizer and
    /// on-device model as production. Its callbacks may restart after utterance
    /// boundaries, so callers must assemble them. Buffer requests can drop
    /// faster-than-real-time file feeds.
    static func makeURLRequest(url: URL) -> SFSpeechURLRecognitionRequest {
        let req = SFSpeechURLRecognitionRequest(url: url)
        configure(req)
        return req
    }
}
