import AVFoundation
import Combine
import Foundation

/// Long-lived audio-session interruption + route-change coordinator.
///
/// Owned by `AppState` so observers stay registered across screen
/// transitions. Decoupled from the ASR backends — both `SpeechRecognizer`
/// and `ParakeetTranscriptStream` keep their existing `start()` / `stop()`
/// API; this coordinator drives those calls when iOS interrupts the mic.
///
/// Design (per `docs/superpowers/specs/2026-05-05-long-form-recording-design.md`
/// section 1):
/// - On `.began`: call `pauseRequested` so the active recognizer
///   stops cleanly. Record `wasRunningAtInterruption` so we know to
///   resume.
/// - On `.ended` with `.shouldResume`: call `resumeRequested` so the
///   recognizer restarts. Append a system transcript line.
/// - On `.ended` without `.shouldResume`: call `stoppedRequested`.
///   Surface a banner; require manual RECORD to come back.
/// - On `.routeChange`: append a system transcript line, do nothing else.
@MainActor
final class AudioSessionCoordinator {

    /// Closure invoked when iOS asks us to pause for an interruption.
    /// AppState wires this to the active recognizer's `stopImmediate()`.
    var pauseRequested: (() async -> Void)?

    /// Closure invoked when iOS clears an interruption with `.shouldResume`.
    /// AppState wires this to a restart of the active recognizer + a system
    /// transcript marker.
    var resumeRequested: (() async -> Void)?

    /// Closure invoked when iOS clears an interruption without `.shouldResume`.
    /// AppState wires this to a banner + leaves the recognizer parked.
    var stoppedRequested: (() async -> Void)?

    /// Closure invoked on any audio route change (headphone disconnect, etc.).
    /// Receives the new port description string. AppState wires this to a
    /// system transcript marker.
    var routeChanged: ((String) -> Void)?

    private var wasRunningAtInterruption = false
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            // Notification is not Sendable; pull out the bits we need
            // before hopping to the main actor.
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }
        observers.append(interruption)

        let route = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRouteChange()
            }
        }
        observers.append(route)
    }

    deinit {
        let center = NotificationCenter.default
        for obs in observers { center.removeObserver(obs) }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard
            let typeRaw,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            wasRunningAtInterruption = true
            Task { await pauseRequested?() }
        case .ended:
            guard wasRunningAtInterruption else { return }
            wasRunningAtInterruption = false
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            if options.contains(.shouldResume) {
                Task { await resumeRequested?() }
            } else {
                Task { await stoppedRequested?() }
            }
        @unknown default:
            return
        }
    }

    private func handleRouteChange() {
        let session = AVAudioSession.sharedInstance()
        let portName = session.currentRoute.outputs.first?.portName ?? "unknown"
        routeChanged?(portName)
    }
}
