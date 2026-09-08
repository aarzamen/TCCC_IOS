import Foundation

struct RecognitionUpdate: Sendable {
    let text: String
    let isFinal: Bool
    let timestamp: Date
    var captureID: UUID? = nil
    var requestID: UUID? = nil
    var termination: CaptureTermination? = nil
    var issue: String? = nil
    var audioUnavailable: Bool = false
    /// Monotonic request-open time; detects decisions preceding the first callback.
    var requestStartedAt: TimeInterval? = nil
}

enum CaptureTermination: String, Sendable {
    case finalized, timedOut, failed, cancelled
}

enum TranscriptStreamError: Error, LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case backendUnavailable(String)
    case alreadyRunning
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:    "Microphone permission denied"
        case .speechDenied:        "Speech recognition permission denied"
        case .recognizerUnavailable: "Speech recognizer unavailable"
        case .onDeviceUnavailable: "On-device speech recognition unavailable on this device — RF Ghost discipline forbids cloud transcription"
        case .backendUnavailable(let msg): msg
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
    /// Optional — used by Apple Speech to commit a debounced partial
    /// and reset the recognition context. Parakeet handles boundaries
    /// via end-of-utterance detection so the default is a no-op.
    func forceFinalize() async
}

extension TranscriptStream {
    func forceFinalize() async { /* default: no-op */ }
}
