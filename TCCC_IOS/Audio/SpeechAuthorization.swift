import Foundation
import Speech

/// TCC delivers permission callbacks on its own queue. Construct the callback
/// outside UI/recognizer isolation and resume the caller's continuation safely.
enum SpeechAuthorization {
    typealias Callback = @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void

    nonisolated static func request(
        current: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus(),
        prompt: @Sendable (@escaping Callback) -> Void = { SFSpeechRecognizer.requestAuthorization($0) }
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            let once = CompletionLatch()
            prompt { @Sendable status in
                if once.claim() { continuation.resume(returning: status) }
            }
        }
    }

    private final class CompletionLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !completed else { return false }
            completed = true
            return true
        }
    }
}
