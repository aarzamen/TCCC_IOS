import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Screen: Int, CaseIterable, Identifiable, Sendable {
        case liveCapture = 0
        case vitals
        case tcccCard
        case medevac
        case handoff

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .liveCapture: "Live Capture"
            case .vitals:      "Vitals"
            case .tcccCard:    "TCCC Card"
            case .medevac:     "MEDEVAC"
            case .handoff:     "Handoff"
            }
        }

        var kicker: String {
            switch self {
            case .liveCapture: "VOICE INTAKE"
            case .vitals:      "PHYSIOLOGY · LIVE"
            case .tcccCard:    "DD-1380 · CASUALTY CARD"
            case .medevac:     "DUSTOFF · 9-LINE REQUEST"
            case .handoff:     "ROLE-1 → ROLE-2 · ENCRYPTED EXPORT"
            }
        }
    }

    enum RFState: Sendable {
        case ghost
        case burst
        case leak
    }

    var screen: Screen = .liveCapture
    var theme: Theme = .tactical
    var settingsOpen: Bool = false
    var quickActionsOpen: Bool = false

    var rfState: RFState = .ghost
    var antPlusArmed: Bool = true
    var jetsonLinkArmed: Bool = true
    var usbConnected: Bool = false

    var casualtyId: String = "C-04"
    var sessionStart: Date = Date()
    var batteryPercent: Int = 78

    var gpsLatitude: Double = 34.5267
    var gpsLongitude: Double = 69.1729

    var transcript: [TranscriptLine] = []
    var partialTranscript: String = ""
    var isRecording: Bool = false
    var recognitionError: String?

    let audioLevels = AudioLevels()

    func appendFinal(_ text: String, speaker: TranscriptLine.Speaker = .medic) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcript.append(TranscriptLine(speaker: speaker, text: trimmed))
        partialTranscript = ""
    }

    func appendSystem(_ text: String) {
        transcript.append(TranscriptLine(speaker: .system, text: text))
    }

    func clearError() {
        recognitionError = nil
    }

    func nextScreen() {
        let last = Screen.allCases.count - 1
        if screen.rawValue < last {
            screen = Screen(rawValue: screen.rawValue + 1) ?? screen
        }
    }

    func previousScreen() {
        if screen.rawValue > 0 {
            screen = Screen(rawValue: screen.rawValue - 1) ?? screen
        }
    }
}
