import Foundation

struct RecognitionUpdate: Sendable {
    let text: String
    let isFinal: Bool
    let timestamp: Date
}

enum TranscriptStreamError: Error, LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case alreadyRunning
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:    "Microphone permission denied"
        case .speechDenied:        "Speech recognition permission denied"
        case .recognizerUnavailable: "Speech recognizer unavailable"
        case .onDeviceUnavailable: "On-device speech recognition unavailable on this device — RF Ghost discipline forbids cloud transcription"
        case .alreadyRunning:      "Already recording"
        case .engineFailed(let msg): "Audio engine failed: \(msg)"
        }
    }
}

protocol TranscriptStream: Sendable {
    func authorize() async throws
    func prime() async throws
    func unprime() async
    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate>
    func stop() async
    func stopImmediate() async
}
