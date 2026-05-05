import AVFoundation
import Foundation

/// Shared audio-capture configuration. Lives outside `AppState` so it can
/// be read from non-`@MainActor` contexts — both ASR backends
/// (`ParakeetTranscriptStream`, `SpeechRecognizer`) are actors, so they
/// cannot reach `@MainActor`-isolated statics across the actor boundary.
///
/// `[String: Any]` is non-`Sendable`, which compounded the isolation
/// problem: even `nonisolated` on the AppState static would still leave
/// the dictionary unable to cross actor contexts under Swift 6 strict
/// concurrency. Putting the constant in a plain non-isolated namespace
/// sidesteps both issues.
enum AudioCaptureConfig {
    /// AAC encoder settings used by both `SpeechRecognizer` and
    /// `ParakeetTranscriptStream`. Voice-quality bitrate (32 kbps) at
    /// the 16 kHz mono sample rate the iPhone mic captures at — yields
    /// ~25 MB/hr vs ~115 MB/hr for the prior WAV PCM format. AAC is the
    /// format `UIActivityViewController` and `Files.app` both render
    /// natively for `.m4a`.
    /// `nonisolated(unsafe)` because `[String: Any]` is non-`Sendable` —
    /// the contents (NSNumber-bridged Ints + a CoreAudio format ID) are
    /// immutable value types, but Swift can't statically prove that
    /// through `Any`. The dictionary is read-only (let), only ever
    /// passed into `AVAudioFile(forWriting:settings:…)`, and never
    /// mutated, so the unchecked annotation is safe in practice.
    nonisolated(unsafe) static let aacOutputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
    ]
}
