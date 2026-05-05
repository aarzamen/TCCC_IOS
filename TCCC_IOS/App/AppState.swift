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

    /// Path to the .wav file that the most recent recording session is being
    /// (or was) captured into. Used by the Handoff Audio Export card.
    var lastRecordingURL: URL?

    let audioLevels = AudioLevels()

    /// Build a fresh audio capture URL inside Documents. The recognizer will
    /// open this for writing on the next start().
    func newAudioCaptureURL() -> URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dateF = DateFormatter()
        dateF.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = dateF.string(from: Date())
        let safeId = casualtyId.replacingOccurrences(of: " ", with: "_")
        return dir.appendingPathComponent("encounter-\(safeId)-\(stamp).wav")
    }

    // Casualty header (currently mock — would come from a roster lookup in production)
    var casualtyName: String = "DOE, J."
    var casualtyUnit: String = "2/75 RGR"
    var casualtyServiceNumberMasked: String = "••• 4471"
    var casualtyAllergies: String = "NKDA"

    // TCCC engine — full 10-pass dispatch per state.py:515–524.
    // var (not let) so newPatient() / wipeSession() can rebuild a fresh engine.
    var engine = PatientStateEngine.standard()
    var primaryPatient: PatientState?
    var allPatients: [String: PatientState] = [:]
    var casualtyCounter: Int = 4

    func appendFinal(_ text: String, speaker: TranscriptLine.Speaker = .medic) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Dedupe: if the most recent line is the same speaker + text, swallow
        // the duplicate. This happens when a UI debounce commits partial text,
        // then SFSpeechRecognizer fires its own isFinal with the same string.
        if let last = transcript.last,
           last.speaker == speaker,
           last.text == trimmed {
            partialTranscript = ""
            return
        }
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
        engine = PatientStateEngine.standard()
        casualtyCounter = 4
        casualtyId = "C-04"
        lastRecordingURL = nil
        encounterNarrative = nil
        zmistNarrative = nil
        transcriptCleaned = nil
    }

    /// Begin a new casualty. Increments the casualty counter, wipes
    /// casualty-specific state, but preserves operator profile, theme, and
    /// RF discipline settings. The previously-active casualty's transcript
    /// and engine state are discarded — by this point the medic is expected
    /// to have already exported via the Handoff screen.
    func newPatient() {
        let oldId = casualtyId
        casualtyCounter += 1
        casualtyId = String(format: "C-%02d", casualtyCounter)
        transcript.removeAll()
        partialTranscript = ""
        recognitionError = nil
        primaryPatient = nil
        allPatients.removeAll()
        sessionStart = Date()
        engine = PatientStateEngine.standard()
        lastRecordingURL = nil
        encounterNarrative = nil
        zmistNarrative = nil
        transcriptCleaned = nil
        appendSystem("NEW CASUALTY · \(casualtyId) · \(oldId) archived")
    }

    /// Mark the current casualty's care as complete. Records the event,
    /// then clears casualty-specific state so the screen is ready for the
    /// next casualty (without incrementing the counter — the medic taps
    /// NEW CASUALTY in Settings when they have a new patient assigned).
    func endCurrentCare() {
        let endedId = casualtyId
        appendSystem("CARE ENDED · \(endedId) · handoff finalized")
        // Snapshot the system line, then clear so the screen resets.
        transcript.removeAll(where: { $0.speaker != .system || !$0.text.contains("CARE ENDED") })
        partialTranscript = ""
        primaryPatient = nil
        allPatients.removeAll()
        engine = PatientStateEngine.standard()
        lastRecordingURL = nil
        encounterNarrative = nil
        zmistNarrative = nil
        transcriptCleaned = nil
    }

    // MARK: - SLM-generated text (persists across screen switches)

    /// 2–3 sentence prose summary of the encounter. Set by the Generate
    /// Narrative button on Handoff. Cleared on lifecycle changes.
    var encounterNarrative: String?

    /// SLM-formatted ZMIST handoff block. Set by the Generate ZMIST button
    /// on Handoff. Cleared on lifecycle changes.
    var zmistNarrative: String?

    /// Cleaned-up version of the transcript with mishearings corrected.
    /// When non-nil, Live Capture renders this instead of `transcript`.
    var transcriptCleaned: [TranscriptLine]?

    // MARK: - Confirmation flow for lifecycle actions

    /// When non-nil, ContentView renders a top-positioned confirmation banner.
    /// Set by `requestConfirmation`, cleared by `confirm` or
    /// `cancelConfirmation`.
    var pendingConfirmation: ConfirmationAction?

    func requestConfirmation(_ action: ConfirmationAction) {
        pendingConfirmation = action
    }

    func confirmPending() {
        guard let action = pendingConfirmation else { return }
        pendingConfirmation = nil
        switch action {
        case .newPatient: newPatient()
        case .endCare:    endCurrentCare()
        case .wipe:       wipeSession()
        }
    }

    func cancelConfirmation() {
        pendingConfirmation = nil
    }
}
