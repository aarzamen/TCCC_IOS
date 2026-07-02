import Speech

/// Single source of SFSpeechRecognizer request configuration. Production
/// capture (SpeechRecognizer) and the DevTools transcription benchmark
/// build requests here, so a config change (vocabulary biasing, task
/// hints, custom LM — sprint WS-3) lands in one place and both lanes
/// measure the same recognizer the app ships.
enum SpeechRequestFactory {
    static func makeBufferRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // RF Ghost hard constraint — cloud transcription is forbidden.
        req.requiresOnDeviceRecognition = true
        return req
    }
}
