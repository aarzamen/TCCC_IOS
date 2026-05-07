import Foundation

/// Placeholder for IBM Granite Speech ASR on iOS.
///
/// Granite Speech currently has no Swift/iOS runtime in this app. Keeping
/// this as a `TranscriptStream` makes the boundary explicit while preventing
/// a selected research backend from opening audio, starting a download, or
/// pretending to be operational.
actor GraniteSpeechTranscriptStream: TranscriptStream {
    private static let unavailableMessage =
        "Granite Speech Swift runtime is not available in this build."

    func authorize() async throws {
        throw TranscriptStreamError.backendUnavailable(Self.unavailableMessage)
    }

    func prime() async throws {
        throw TranscriptStreamError.backendUnavailable(Self.unavailableMessage)
    }

    func unprime() async {
        // No runtime resources exist to release.
    }

    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> {
        throw TranscriptStreamError.backendUnavailable(Self.unavailableMessage)
    }

    func stop() async {
        // Nothing was started.
    }

    func stopImmediate() async {
        // Nothing was started.
    }
}
