import Foundation
import Observation
import TCCCDomain
import TCCCExtractor

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

    // Casualty header (currently mock — would come from a roster lookup in production)
    var casualtyName: String = "DOE, J."
    var casualtyUnit: String = "2/75 RGR"
    var casualtyServiceNumberMasked: String = "••• 4471"
    var casualtyAllergies: String = "NKDA"

    // TCCC engine — full 10-pass dispatch per state.py:515–524.
    let engine = PatientStateEngine.standard()
    var primaryPatient: PatientState?
    var allPatients: [String: PatientState] = [:]

    func appendFinal(_ text: String, speaker: TranscriptLine.Speaker = .medic) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcript.append(TranscriptLine(speaker: speaker, text: trimmed))
        partialTranscript = ""
        Task { await processWithEngine(trimmed) }
    }

    func appendSystem(_ text: String) {
        transcript.append(TranscriptLine(speaker: .system, text: text))
    }

    func clearError() {
        recognitionError = nil
    }

    private func processWithEngine(_ text: String) async {
        await engine.processTranscript(text, timestamp: Date())
        await refreshPatientSnapshot()
    }

    func refreshPatientSnapshot() async {
        let snapshot = await engine.snapshot()
        allPatients = snapshot
        // Single-casualty UI per design §9 — surface PATIENT_1 only.
        primaryPatient = snapshot["PATIENT_1"]
        // Record a vitals sample for the Screen 02 trend chart. Buffer is
        // self-pruning to a 15-minute window (see VitalsHistory).
        vitalsHistory.record(from: primaryPatient?.vitals ?? Vitals(), at: Date())
    }

    func loadDemoTranscript(_ text: String) async {
        transcript.removeAll()
        partialTranscript = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            transcript.append(TranscriptLine(speaker: .medic, text: line))
        }
        await engine.processTranscript(text, timestamp: Date())
        await refreshPatientSnapshot()
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

    // MARK: - Handoff (Screen 05) state additions

    var selectedHandoffDestination: HandoffDestination = .qr
    var qrOverlayVisible: Bool = false

    // MARK: - Settings — operator profile + system flags

    var operatorCallsign: String = "HAVOC 2A"
    var operatorRole: String = "68W · SR MEDIC"
    var operatorUnit: String = "2/75 RGR"
    var operatorDeviceId: String = "EUD-441-C"

    var voiceCommandsEnabled: Bool = true
    var hapticFeedbackEnabled: Bool = true
    var lockOrientationEnabled: Bool = true
    var screenBurnProtectionEnabled: Bool = true
    var autoExportOnWiredHandoffEnabled: Bool = false

    func wipeSession() {
        transcript.removeAll()
        partialTranscript = ""
        recognitionError = nil
        primaryPatient = nil
        allPatients.removeAll()
        sessionStart = Date()
        vitalsHistory = VitalsHistory()
        // Engine retains previously-extracted state across calls; spawning a
        // new engine would also do it, but processTranscript-on-empty plus
        // clearing the snapshot is enough for the current single-casualty UI.
    }

    // MARK: - Vitals trend (Screen 02) — rolling 15-min sample buffer

    /// Rolling buffer of vitals samples, recorded each time the engine
    /// snapshot refreshes. Drives the TrendChart on Screen 02.
    var vitalsHistory = VitalsHistory()
}
