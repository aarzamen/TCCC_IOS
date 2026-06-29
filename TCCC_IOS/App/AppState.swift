import AVFoundation
import Foundation
import Observation
import os
import TCCCAudio
import TCCCDomain
import TCCCExtractor
import TCCCReports
import UIKit

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
            case .vitals:      "Vital Signs Log"
            case .tcccCard:    "TCCC Card"
            case .medevac:     "MEDEVAC"
            case .handoff:     "Handoff"
            }
        }

        var kicker: String {
            switch self {
            case .liveCapture: "VOICE INTAKE"
            case .vitals:      "DD 1380 · SECTION C"
            case .tcccCard:    "DD-1380 · CASUALTY CARD"
            case .medevac:     "9-LINE MEDEVAC"
            case .handoff:     "ROLE-1 → ROLE-2 EXPORT"
            }
        }
    }

    enum RFState: Sendable {
        case ghost
        case burst
        case leak
    }

    /// TCCC responder tier per JTS taxonomy. Drives scope-of-practice
    /// gating like the ASM/CLS TQ-conversion 2-hour rule (2026 sprint 2.5,
    /// 2026 §6 ASM/CLS scope safeguard).
    enum OperatorTier: String, Sendable, CaseIterable {
        /// All Service Members — basic individual lifesaver level.
        case asm = "ASM"
        /// Combat Lifesaver — non-medical squad/team designee.
        case cls = "CLS"
        /// Combat Medic / Corpsman — primary unit medical provider.
        case cmc = "CMC"
        /// Combat Paramedic / Provider — advanced medical provider.
        case cpp = "CPP"

        /// True when scope-of-practice limits ASM/CLS personnel from
        /// independently performing TQ conversion beyond 2 hours per
        /// 2026 §6.
        var isASMOrCLS: Bool { self == .asm || self == .cls }
    }

    /// Non-blocking warnings surfaced from rubric-mandated rules.
    enum TCCCWarning: Sendable, Hashable {
        /// 2026 §11 — AVPU must be documented prior to ketamine
        /// administration. Fires when ketamine is logged but AVPU
        /// (consciousness) is unset.
        case avpuBeforeKetamine
        /// 2026 §6 — ASM/CLS personnel must not attempt TQ conversion
        /// beyond 2 hours post-application without CMC/CPP direction.
        case tqConversionScope
    }

    var screen: Screen = .liveCapture
    /// Default theme is **Dark** per night-pass A4 (2026-05-05). Tactical
    /// (deep near-black + desaturated red) remains a selectable option in
    /// Settings — only the initial value flipped. The previous default
    /// drew complaints in non-NVG conditions ("red hell theme").
    var theme: Theme = .dark
    var settingsOpen: Bool = false
    var quickActionsOpen: Bool = false
    var reviewOpen: Bool = false

    var rfState: RFState = .ghost

    /// ASR backend selection per night-pass Track B (2026-05-05).
    /// Apple Speech is the proven default. Parakeet is on ice — the
    /// actor compiles and is reachable behind this toggle, but
    /// requires the operator to supply a model directory before
    /// `start()` will succeed. Granite Speech is an alternate ASR
    /// (per Granite Speech Foundation Sprint 1 v3 §G1, 2026-05-10);
    /// requires a configured local Granite Speech model folder via
    /// Settings → "Select Granite Speech Model Folder" before
    /// `start()` will succeed.
    enum ASRBackend: String, Sendable, CaseIterable, Identifiable, Codable {
        case appleSpeech
        case parakeet
        case graniteSpeech
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .appleSpeech:   "Apple Speech"
            case .parakeet:      "Parakeet (alt)"
            case .graniteSpeech: "Granite Speech (alt)"
            }
        }
    }
    var asrBackend: ASRBackend = .appleSpeech

    /// Filesystem path to the Parakeet CoreML model directory. Set
    /// from Settings when the operator AirDrops or downloads the
    /// model bundle. Nil → Parakeet backend uses FluidAudio's auto-
    /// download path on first start().
    var parakeetModelDirectory: URL?

    /// Persistent security-scoped bookmark store for the Granite
    /// Speech model folder (Granite Speech Foundation Sprint 1 v3
    /// §G1, 2026-05-10). The operator selects a folder once via
    /// Settings → "Select Granite Speech Model Folder"; the bookmark
    /// survives app reinstalls when the folder lives in user-managed
    /// iCloud Drive or "On My iPhone" storage. The runtime in
    /// TCCCAudio reads the same UserDefaults key by default, so this
    /// shared instance keeps Settings and runtime in sync.
    let graniteSpeechBookmarkStore = GraniteSpeechBookmarkStore()

    /// Lifecycle state of the Parakeet model bundle on disk.
    enum ParakeetStatus: Sendable, Equatable {
        case unknown
        case notDownloaded
        case downloading(fraction: Double)   // 0.0 .. 1.0
        case ready
        case failed(message: String)
    }
    var parakeetStatus: ParakeetStatus = .unknown

    // MARK: - Audio gain (variable dynamic mic gain)

    /// Microphone input gain in decibels. Slider range -20 to +20.
    /// 0 dB is unchanged, +6 dB is ~2× louder, +12 dB is ~4× louder,
    /// -6 dB is half as loud. Applied uniformly to both ASR
    /// backends in their audio-tap callbacks before recognition.
    var audioGainDb: Float = 0.0 {
        didSet { audioGainBox.linear = powf(10.0, audioGainDb / 20.0) }
    }

    /// Linear gain multiplier derived from `audioGainDb`. Closures in
    /// the audio actors snapshot this at each tap callback so changes
    /// take effect on the next sample, not just the next start().
    var audioGainLinear: Float {
        powf(10.0, audioGainDb / 20.0)
    }

    /// Sendable, non-isolated gain accessor. The audio tap callback
    /// runs on AVAudioEngine's render thread (not MainActor); reading
    /// `audioGainDb` from there via `MainActor.assumeIsolated` is a
    /// fatal trap. This box is the bridge: SwiftUI updates `linear`
    /// on the MainActor; the audio thread reads it without isolation.
    /// `OSAllocatedUnfairLock` provides actual race-safety — assuming
    /// "Float reads are atomic on Apple Silicon" is a lottery ticket
    /// the language model owes us nothing on. The lock is uncontended
    /// in practice (one writer, one reader, ~50 Hz) so the cost is
    /// invisible to the operator.
    final class AudioGainBox: @unchecked Sendable {
        private let storage = OSAllocatedUnfairLock<Float>(initialState: 1.0)
        var linear: Float {
            get { storage.withLock { $0 } }
            set { storage.withLock { $0 = newValue } }
        }
    }
    let audioGainBox = AudioGainBox()

    // MARK: - Long-form recording infrastructure (Wave 3 L1.3 + L3.3)

    /// Long-lived AVAudioSession interruption + route observer. Lives
    /// for the AppState lifetime so observers stay registered across
    /// page swipes.
    let audioSessionCoordinator = AudioSessionCoordinator()

    /// Set true by AudioSessionCoordinator when iOS interrupts. LiveCaptureScreen
    /// observes via .onChange and stops the recognizer cleanly.
    var pendingInterruptionPause: Bool = false

    /// Set true by AudioSessionCoordinator when iOS clears a resumable
    /// interruption. LiveCaptureScreen observes via .onChange and restarts.
    var pendingInterruptionResume: Bool = false

    /// Set when an interruption ends without `.shouldResume`. LiveCaptureScreen
    /// surfaces a banner and asks operator to manually re-tap RECORD.
    var interruptionRequiresManualRestart: Bool = false

    /// Memory-pressure observer. Force-commits the in-flight partial
    /// when iOS reports critical pressure mid-90-min recording.
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init() {
        // L1.3 — AudioSessionCoordinator closures. AudioSessionCoordinator
        // is itself @MainActor-isolated; its closures run on MainActor,
        // so we don't need an extra MainActor.run hop.
        audioSessionCoordinator.pauseRequested = { [weak self] in
            guard let self else { return }
            self.pendingInterruptionPause = true
            self.appendSystem("INTERRUPTED · audio session preempted")
        }
        audioSessionCoordinator.resumeRequested = { [weak self] in
            guard let self else { return }
            let stamp = Self.timeStamp()
            self.appendSystem("RESUMED · \(stamp)")
            self.pendingInterruptionResume = true
        }
        audioSessionCoordinator.stoppedRequested = { [weak self] in
            guard let self else { return }
            self.interruptionRequiresManualRestart = true
            self.appendSystem("INTERRUPTION ENDED · tap RECORD to resume")
        }
        audioSessionCoordinator.routeChanged = { [weak self] portName in
            self?.appendSystem("ROUTE · \(portName)")
        }

        // L3.3 — memory-pressure observer
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            // The handler runs on the queue we registered (.main), but
            // Dispatch can't statically prove MainActor isolation.
            MainActor.assumeIsolated {
                guard let self else { return }
                let event = src.mask
                if event.contains(.critical) {
                    self.appendSystem("MEMORY · critical pressure · committing partial")
                    if !self.partialTranscript.isEmpty {
                        self.appendFinal(self.partialTranscript)
                        self.partialTranscript = ""
                    }
                } else if event.contains(.warning) {
                    let logger = Logger(subsystem: "ai.tccc", category: "memory")
                    logger.warning("memory: warning event received")
                }
            }
        }
        src.resume()
        self.memoryPressureSource = src

        // Enable live battery reporting for the status strip. Local device
        // API only — no network, no prompt. Returns -1 on the simulator.
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    private static func timeStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ssZ"
        return f.string(from: Date())
    }

    // MARK: - Parakeet model lifecycle (B2)

    /// Active download task — non-nil while a download is running.
    /// Settings UI uses this to disable the button mid-flight.
    private var parakeetDownloadTask: Task<Void, Never>?

    /// Begin downloading the Parakeet CoreML model bundle from
    /// FluidInference's Hugging Face repo. Single HTTPS GET, gated
    /// here behind explicit operator consent (Settings tap). Once the
    /// bundle is cached in Application Support, the app never makes
    /// another network call for ASR — RF Ghost is preserved.
    /// No-op if a download is already running.
    func beginParakeetDownload() {
        if parakeetDownloadTask != nil { return }
        parakeetStatus = .downloading(fraction: 0.0)
        parakeetDownloadTask = Task { [weak self] in
            await Self.runParakeetDownload(notifying: { @Sendable status in
                Task { @MainActor in
                    guard let self = await self else { return }
                    self.parakeetStatus = status
                    if case .ready = status {
                        self.parakeetDownloadTask = nil
                    }
                    if case .failed = status {
                        self.parakeetDownloadTask = nil
                    }
                }
            })
        }
    }

    /// Static download driver — no actor isolation, no `self` capture
    /// trickery. Posts every status transition through the supplied
    /// @Sendable callback so the MainActor side can update UI state
    /// cleanly.
    private static func runParakeetDownload(
        notifying notify: @escaping @Sendable (ParakeetStatus) -> Void
    ) async {
        let stream = ParakeetTranscriptStream(levels: nil)
        await stream.setDownloadProgressHandler { fraction in
            notify(.downloading(fraction: fraction))
        }
        do {
            try await stream.ensureModelsLoaded()
            notify(.ready)
        } catch {
            notify(.failed(message: error.localizedDescription))
        }
    }

    /// LLM backend selection per night-pass Track C (2026-05-05).
    /// Apple Foundation Models is the proven default. LFM2.5 is the
    /// recommended general alt (LFM Open License, no medical/military
    /// AUP); Qwen 3 1.7B is an Apache-2.0 fallback for that slot.
    /// Granite 4.0 H 1B Base is the explicit hot-seat text backend for
    /// evidence-bounded candidate patches.
    enum LLMBackend: String, Sendable, CaseIterable, Identifiable, Codable {
        case appleFoundation
        case lfm2
        case qwen3
        case graniteText
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .appleFoundation: "Apple Foundation Models"
            case .lfm2:            "Liquid LFM2.5 1.2B (alt)"
            case .qwen3:           "Qwen 3 1.7B (alt)"
            case .graniteText:     "IBM Granite 4.0 H 1B Base"
            }
        }
    }
    var llmBackend: LLMBackend = .appleFoundation

    /// Which LLM backend (if any) is currently fetching weights via the
    /// Settings DOWNLOAD affordance. `nil` = idle. Settings UI binds to
    /// this to swap the per-row DOWNLOAD button for a spinner. Single-
    /// flight: `downloadBackendWeights(_:)` short-circuits if already set.
    var downloadingBackend: LLMBackend? = nil

    /// Pre-fetch the selected backend's weights into the on-disk HF Hub
    /// cache. Drives the Settings DOWNLOAD button: tap → spinner →
    /// `availability` flips to `.available` once the snapshot directory
    /// is populated. Apple Foundation Models is a no-op here — Apple
    /// manages weight delivery via system update.
    ///
    /// Single-flight: bails immediately if another download is in
    /// progress, so the operator can tap freely without queuing
    /// duplicate fetches.
    func downloadBackendWeights(_ backend: LLMBackend) async {
        guard downloadingBackend == nil else { return }
        downloadingBackend = backend
        defer { downloadingBackend = nil }

        switch backend {
        case .appleFoundation:
            return  // managed by Apple — nothing to fetch
        case .lfm2:
            do {
                try await LFM2LLMBackend().prefetch()
            } catch {
                appendSystem("DOWNLOAD FAILED · \(backend.displayName) · \(error.localizedDescription)")
            }
        case .qwen3:
            do {
                try await QwenLLMBackend().prefetch()
            } catch {
                appendSystem("DOWNLOAD FAILED · \(backend.displayName) · \(error.localizedDescription)")
            }
        case .graniteText:
            do {
                try await GraniteTextLLMBackend().prefetch()
            } catch {
                appendSystem("DOWNLOAD FAILED · \(backend.displayName) · \(error.localizedDescription)")
            }
        }
    }

    /// Provenance of the casualty location used for 9-line LINE 1.
    /// Production model: the only real source is the iPhone's GPS. The
    /// former `.manual` (typed lat/lon) and `.demo` (hardcoded Bagram
    /// training coords) development modes were removed — neither read the
    /// device's real position, so neither may drive a transmitted Line 1.
    enum LocationSource: String, Codable, Sendable, CaseIterable, Identifiable {
        case none   // no fix — Line 1 must be marked UNVERIFIED
        case gps    // real one-shot CoreLocation fix
        var id: String { rawValue }
        var badge: String {
            switch self {
            case .none: "NO FIX"
            case .gps:  "GPS"
            }
        }
    }

    /// A captured position plus the GPS metadata an operator needs to judge
    /// it. Transient app state only — never written to the event log, the
    /// manifest, or any export. The new metadata fields default to `nil` so
    /// existing `LocationFix(source: .none, latitude: nil, longitude: nil)`
    /// call sites still compile.
    struct LocationFix: Codable, Sendable, Equatable {
        var source: LocationSource
        var latitude: Double?
        var longitude: Double?
        var horizontalAccuracyMeters: Double? = nil
        var verticalAccuracyMeters: Double?   = nil
        var capturedAt: Date?                 = nil
        var authorizationStatusDescription: String?   = nil
        var accuracyAuthorizationDescription: String? = nil
        /// True only for a real GPS fix with non-nil lat/lon.
        var isUsable: Bool { source == .gps && latitude != nil && longitude != nil }
    }

    var casualtyId: String = "C-04"
    var sessionStart: Date = Date()

    /// Live battery charge as a whole percent, read from the device each
    /// time the status strip ticks (1 Hz). `-1` when unknown (simulator, or
    /// monitoring unavailable) so the UI can render a placeholder. Replaces
    /// the former hardcoded `78`.
    var batteryPercent: Int {
        let level = UIDevice.current.batteryLevel   // 0.0–1.0, or -1 if unknown
        guard level >= 0 else { return -1 }
        return Int((level * 100).rounded())
    }

    /// True while the device is charging or full (drives a charging glyph).
    var batteryIsCharging: Bool {
        switch UIDevice.current.batteryState {
        case .charging, .full: return true
        default:               return false
        }
    }

    /// Wall-clock timestamp of the most recent successful MEDEVAC transmit
    /// (set by `HandoffScreen.completeTransmit` when the destination is
    /// functional, e.g. QR · OFFLINE). `nil` until the operator has actually
    /// sent the packet. Drives the `MEDEVAC requested` row in the Handoff
    /// timeline so it never appears for an unsent encounter.
    var lastMedevacTransmitTime: Date? = nil

    /// No silent default position. Stays `.none` (Line 1 renders
    /// UNVERIFIED) until the operator taps USE GPS FIX on the MEDEVAC
    /// screen and a real CoreLocation fix lands.
    var locationFix: LocationFix = LocationFix(source: .none, latitude: nil, longitude: nil)

    /// Drives the MEDEVAC USE GPS FIX control's status label. One-to-one
    /// with the spec's labels: NO FIX / REQUESTING GPS / GPS FIX ± Xm /
    /// GPS DEGRADED ± Xm / GPS DENIED / GPS RESTRICTED / MGRS UNAVAILABLE.
    enum LocationCaptureStatus: Equatable {
        case noFix
        case requesting
        case fix(accuracyMeters: Double?)
        case degraded(accuracyMeters: Double?)
        case denied
        case restricted
        case mgrsUnavailable
    }

    var locationStatus: LocationCaptureStatus = .noFix

    /// Full-precision MGRS grid for the current fix (e.g. `42S WD 15867
    /// 20571`), or `nil` when there is no usable fix or the coordinate is
    /// unencodable. Drives the always-visible status-strip readout so the
    /// operator can read their position from any screen.
    var locationGrid: String? {
        guard locationFix.isUsable,
              let lat = locationFix.latitude,
              let lon = locationFix.longitude else { return nil }
        return MGRS.formatted(latitude: lat, longitude: lon)
    }

    /// Horizontal-accuracy ceiling (metres) above which an otherwise-valid
    /// fix is surfaced as GPS DEGRADED. Field-tunable starting value.
    static let degradedAccuracyThreshold: Double = 100

    /// The real GPS source. Injectable so tests can substitute a stub;
    /// production always uses the CoreLocation one-shot provider. Observation
    /// is ignored — it is plumbing, not observable UI state.
    @ObservationIgnored
    var locationProvider: LocationProviding = CoreLocationProvider()

    /// Acquire a one-shot GPS fix and classify it into `locationStatus`,
    /// storing the position in the observable `locationFix` (the MEDEVAC
    /// `form` recomputes LINE 1 from it).
    ///
    /// Called automatically at launch and before document generation with
    /// `silent: true`, and manually from USE GPS FIX with `silent: false`.
    /// A silent refresh does not flash REQUESTING when a usable fix already
    /// exists and does not downgrade that fix on a transient miss — so a
    /// momentary no-fix while generating a ZMIST/MEDEVAC can't blank a grid
    /// the operator is about to transmit. Still strictly one-shot: no
    /// continuous tracking, no background updates. Requests the system
    /// permission the first time only; never crashes on denied/restricted.
    func captureGPSFix(silent: Bool = false) async {
        let priorUsable = locationFix.isUsable
        if !silent || !priorUsable { locationStatus = .requesting }
        do {
            let fix = try await locationProvider.requestOneShotFix()
            if let lat = fix.latitude, let lon = fix.longitude {
                // Full-precision MGRS only — no decimal fallback.
                if MGRS.formatted(latitude: lat, longitude: lon) != nil {
                    locationFix = fix
                    locationStatus = classifyFix(fix)
                } else {
                    // A real position MGRS cannot encode (polar/UPS).
                    locationFix = fix
                    locationStatus = .mgrsUnavailable
                }
            } else if priorUsable {
                locationStatus = classifyFix(locationFix)   // keep the prior fix
            } else {
                locationStatus = .noFix
            }
        } catch LocationError.denied {
            locationStatus = .denied
        } catch LocationError.restricted {
            locationStatus = .restricted
        } catch {
            // Transient miss: keep a prior good fix rather than blank it.
            locationStatus = priorUsable ? classifyFix(locationFix) : .noFix
        }
    }

    /// Classify a usable fix into GPS FIX vs GPS DEGRADED. Reduced accuracy
    /// authorization or horizontal accuracy beyond the threshold degrades.
    private func classifyFix(_ fix: LocationFix) -> LocationCaptureStatus {
        let reduced = fix.accuracyAuthorizationDescription == LocationAccuracyTag.reduced
        let poor = (fix.horizontalAccuracyMeters ?? 0) > Self.degradedAccuracyThreshold
        return (reduced || poor)
            ? .degraded(accuracyMeters: fix.horizontalAccuracyMeters)
            : .fix(accuracyMeters: fix.horizontalAccuracyMeters)
    }

    /// Settle window in seconds: if a provisional is not revised by a final echo
    /// within this interval, the timer fires `promoteProvisional()` and the chunk
    /// is committed as-is. 2.0 s matches the SFSpeechRecognizer silence-trigger
    /// calibrated during the silence-debounce sprint.
    static let settleWindow: TimeInterval = 2.0

    var transcript: [TranscriptLine] = []
    var transcriptLedger = TranscriptSegmentLedger()
    var partialTranscript: String = ""

    /// Identity of the outstanding provisional transcript line, or nil. While non-nil,
    /// the next refined `isFinal` echo revises it in place; STOP/interruption/timeout/
    /// a new commit promote it to permanent first.
    private var provisionalLineId: TranscriptLine.ID?
    private var provisionalSettleTask: Task<Void, Never>?
    /// Serializes engine mutations (commit / revise / settle) so they execute in
    /// submission order regardless of scheduler. Each new engine op awaits the prior
    /// task's value before proceeding, preventing applyFinalEcho's reviseProvisional
    /// from running before commitProvisional's boundary has been set in the engine.
    private var provisionalEngineTask: Task<Void, Never>?

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
        return dir.appendingPathComponent("encounter-\(safeId)-\(stamp).m4a")
    }

    // Casualty header (currently mock — would come from a roster lookup in production)
    var casualtyName: String = "DOE, J."
    var casualtyUnit: String = "2/75 RGR"
    var casualtyServiceNumberMasked: String = "••• 4471"
    var casualtyAllergies: String = "NKDA"

    /// Base directory for casualty persistence. Injectable for tests; defaults to Documents.
    var documentsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
    /// On-disk encounter store (nil until `load()` configures it).
    var encounterStore: EncounterStore?
    /// Count of engine log events already flushed to disk. Cursor-guards persistence.
    private(set) var persistedCursor: Int = 0
    /// Serializes `persistNewEvents()` against itself so two fire-and-forget callers
    /// cannot read the same cursor and slice overlapping event ranges. See persistNewEvents.
    private var isPersisting = false
    private var persistAgain = false

    // TCCC engine — full 10-pass dispatch per state.py:515–524.
    // var (not let) so newPatient() / wipeSession() can rebuild a fresh engine.
    var engine = PatientStateEngine.standard()
    var primaryPatient: PatientState?
    var allPatients: [String: PatientState] = [:]
    var casualtyCounter: Int = 4
    var graniteReviewQueue: [GraniteReviewItem] = []

    /// Most recent contradiction surfaced by the apply path (engine value vs model
    /// value). Held for review; the engine value remains shown until the operator
    /// actively overrides. `nil` when there is no pending conflict.
    var lastConflictMessage: String?

    /// Compatibility entry used by tests and any non-streaming caller: treat as a
    /// fresh final (commit + immediate settle).
    func appendFinal(
        _ text: String,
        speaker: TranscriptLine.Speaker = .medic,
        timestamp: Date = Date()
    ) {
        guard speaker == .medic else {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            transcript.append(TranscriptLine(speaker: speaker, text: t, timestamp: timestamp))
            return
        }
        commitProvisional(text, timestamp: timestamp)
        promoteProvisional()
    }

    /// Commit a chunk as provisional (loss-safe, on screen now). Promotes any prior
    /// provisional first (succession), then opens the settle window.
    func commitProvisional(_ text: String, timestamp: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if provisionalLineId != nil { promoteProvisional() }
        let line = TranscriptLine(speaker: .medic, text: trimmed, timestamp: timestamp)
        transcript.append(line)
        provisionalLineId = line.id
        partialTranscript = ""
        let prior0 = provisionalEngineTask
        let eng0 = engine   // capture at submission time; lifecycle reset can't target new engine
        provisionalEngineTask = Task { @MainActor in
            await prior0?.value
            // Short-circuit if a lifecycle reset (wipe/newPatient/endCare) cancelled this
            // chain while it was suspended. The captured `eng0` also prevents the op below
            // from targeting a post-swap engine even if the check were somehow skipped.
            if Task.isCancelled { return }
            await eng0.commitProvisional(trimmed, timestamp: timestamp)
            await refreshPatientSnapshot(persist: false)   // defer persist until settle
        }
        if let cmd = detectVoiceCommand(in: trimmed) { armVoiceCommand(cmd) }
        startSettleTimer()
    }

    /// A refined `isFinal` echo. Revise the outstanding provisional in place, else
    /// commit-and-settle a fresh final.
    func applyFinalEcho(_ text: String, timestamp: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let id = provisionalLineId,
              let idx = transcript.firstIndex(where: { $0.id == id }) else {
            commitProvisional(text, timestamp: timestamp); promoteProvisional(); return
        }
        provisionalSettleTask?.cancel(); provisionalSettleTask = nil
        transcript[idx] = TranscriptLine(speaker: .medic, text: trimmed, timestamp: timestamp)
        provisionalLineId = transcript[idx].id
        let prior1 = provisionalEngineTask
        let eng1 = engine   // capture at submission time; lifecycle reset can't target new engine
        provisionalEngineTask = Task { @MainActor in
            await prior1?.value
            if Task.isCancelled { return }
            await eng1.reviseProvisional(trimmed, timestamp: timestamp)
            await refreshPatientSnapshot(persist: false)
            promoteProvisional()
        }
    }

    /// Settle the outstanding provisional: it becomes permanent and is persisted.
    func promoteProvisional() {
        provisionalSettleTask?.cancel(); provisionalSettleTask = nil
        guard let id = provisionalLineId,
              let line = transcript.first(where: { $0.id == id }) else { return }
        provisionalLineId = nil
        // Populate the export/Granite ledger with the SETTLED (possibly refined) text.
        appendTranscriptEvidence(line.text, timestamp: line.timestamp)
        let prior2 = provisionalEngineTask
        let eng2 = engine   // capture at submission time; lifecycle reset can't target new engine
        provisionalEngineTask = Task { @MainActor in
            await prior2?.value
            if Task.isCancelled { return }
            await eng2.settleProvisional()
            await refreshPatientSnapshot(persist: true)   // flush the settled chunk
        }
    }

    private func startSettleTimer() {
        provisionalSettleTask?.cancel()
        provisionalSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AppState.settleWindow * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.promoteProvisional()
        }
    }

    func appendSystem(_ text: String) {
        transcript.append(TranscriptLine(speaker: .system, text: text))
    }

    private func appendTranscriptEvidence(_ text: String, timestamp: Date) {
        let endMs = max(0, Int(timestamp.timeIntervalSince(sessionStart) * 1_000))
        let priorEndMs = transcriptLedger.normalizedSegments.last?.endMs ?? 0
        let startMs = min(priorEndMs, endMs)
        transcriptLedger.appendRaw(
            text: text,
            startMs: startMs,
            endMs: max(endMs, startMs),
            backend: currentTranscriptBackend,
            isFinal: true
        )
    }

    private var currentTranscriptBackend: TranscriptBackend {
        switch asrBackend {
        case .appleSpeech:   .appleSpeech
        case .parakeet:      .parakeet
        case .graniteSpeech: .graniteSpeech
        }
    }

    func clearError() {
        recognitionError = nil
    }

    private func processWithEngine(_ text: String, timestamp: Date) async {
        await engine.processTranscript(text, timestamp: timestamp)
        await refreshPatientSnapshot()
    }

    func refreshPatientSnapshot(persist: Bool = true) async {
        let snapshot = await engine.snapshot()
        allPatients = snapshot
        // Single-casualty UI per design §9 — surface PATIENT_1 only.
        primaryPatient = snapshot["PATIENT_1"]
        // 2026 sprint Phase 4 — record a §C reading per snapshot. The grid
        // shows the 4 most recent readings.
        let didAppendVitals = appendVitalsSnapshot()
        if persist {
            await persistNewEvents()                // skip on provisional commits; flush on settle
            if didAppendVitals { await persistSectionC() }
        }
    }

    /// Flush any engine-log events beyond the cursor to the active casualty's file.
    /// Cursor-guarded ⇒ idempotent and safe to call after every engine mutation.
    ///
    /// Serialized against itself. `persistNewEvents` is invoked from multiple
    /// fire-and-forget `Task`s — per committed ASR line via `appendFinal`, and from
    /// `GraniteReviewQueue`. The body crosses two awaits between reading `persistedCursor`
    /// and advancing it, so two concurrent invocations would otherwise read the SAME
    /// cursor, slice overlapping `[cursor...]` ranges, and both append — duplicating
    /// events on disk AND (because the cursor advances relatively) over-advancing it so
    /// later events are skipped. The guard lets only one drain run at a time; a call that
    /// arrives mid-drain just sets `persistAgain`, and the active drain loops to pick up
    /// whatever it newly missed. Only the active invocation ever reads or advances
    /// `persistedCursor`, so each slice is exact — no overlap, no skip. The flag reads and
    /// writes never straddle an await, so on `@MainActor` (a serial executor) they are
    /// atomic with respect to reentrancy.
    // INVARIANT (provisional-replace): while a provisional chunk is outstanding
    // (`engine.hasProvisional`), it is the log tail and may be truncated by
    // `engine.reviseProvisional`. We therefore flush only on settle
    // (`promoteProvisional` → `refreshPatientSnapshot(persist: true)`), never on the
    // provisional commit/revise refreshes (`persist: false`). The append-only JSONL
    // cannot un-write a line, so flushing an unsettled chunk would strand gen-0 events
    // on disk after a revise truncates them. The other `persist: true` callers
    // (operator accept/reject, lifecycle) are safe because each first appends a foreign
    // engine event, which trips `reviseProvisional`'s tail-guard into its no-truncate
    // fallback. If you add a new `persist: true` path, ensure it cannot run mid-provisional
    // without a preceding foreign event.
    func persistNewEvents() async {
        guard let store = encounterStore else { return }
        if isPersisting { persistAgain = true; return }
        isPersisting = true
        defer { isPersisting = false }
        repeat {
            persistAgain = false
            let new = await engine.newEvents(since: persistedCursor)
            guard !new.isEmpty else { continue }
            do {
                try await store.appendToActive(new)
                persistedCursor += new.count
            } catch {
                appendSystem("PERSIST FAILED · \(error.localizedDescription)")
            }
        } while persistAgain
    }

    /// Replay-on-launch: recover an in-progress encounter from disk, or open a fresh
    /// casualty dir for this session. Call once at app launch.
    func load() async {
        let store = EncounterStore(baseURL: documentsURL)
        encounterStore = store
        do {
            if let (id, log) = try await store.loadActiveEncounter() {
                casualtyId = id
                await engine.restore(log)
                persistedCursor = log.events.count
                // Restore the persisted §C grid BEFORE the snapshot refresh so
                // the rolling buffer (and the DD1380 export) survives recovery;
                // the refresh then appends the current reading (deduped).
                if let scData = await store.loadSectionC(),
                   let restored = try? Self.sectionCCodec.decoder.decode([SectionCReading].self, from: scData) {
                    vitalsLog = restored
                }
                await refreshPatientSnapshot()        // cursor up-to-date ⇒ persists nothing
                appendSystem("RECOVERED · \(id) · \(log.events.count) events replayed")
            } else {
                try await store.startNewCasualty(id: casualtyId, startUnix: Date().timeIntervalSince1970)
                persistedCursor = 0
                await persistNewEvents()              // flush the fresh engine's lc-1 seed
            }
        } catch {
            appendSystem("PERSIST INIT FAILED · \(error.localizedDescription)")
        }

        // Acquire an initial GPS fix at startup so LINE 1 is populated
        // without an operator tap. On first launch this drives the system
        // permission prompt; once granted it is silent on every later
        // launch. Fire-and-forget so it never delays encounter restore.
        Task { await captureGPSFix(silent: true) }
    }

#if DEBUG
    func processWithEngineForTest(_ text: String) async { await processWithEngine(text, timestamp: Date()) }
#endif

    // MARK: - DD 1380 §C grid (sprint Phase 4 Task 4.2)

    /// One timestamped column of the DD 1380 Section C vital-sign grid.
    /// The form supports up to 4 columns; the rolling buffer keeps the
    /// most recent 4 readings.
    struct SectionCReading: Sendable, Identifiable, Hashable, Codable {
        let id: UUID
        let timestamp: Date
        let vitals: Vitals
        let avpu: String?

        init(timestamp: Date, vitals: Vitals, avpu: String?) {
            self.id = UUID()
            self.timestamp = timestamp
            self.vitals = vitals
            self.avpu = avpu
        }

        /// Convert to the pure DD1380 grid column (pre-formatted display
        /// strings; AVPU text → letter; no pain source in Vitals → blank).
        func toDD1380() -> DD1380SectionCReading {
            // Local formatter: a static one on @MainActor AppState can't be
            // referenced from this nonisolated nested type.
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "HHmm"
            return DD1380SectionCReading(
                timeHHMM: f.string(from: timestamp),
                pulse: vitals.hr.map(String.init),
                bloodPressure: vitals.bp.map { "\($0.systolic)/\($0.diastolic)" },
                respiratoryRate: vitals.rr.map(String.init),
                spo2: vitals.spo2.map(String.init),
                avpu: DD1380Mapper.avpuLetter(avpu),
                pain: nil
            )
        }
    }

    private static let sectionCCodec: (encoder: JSONEncoder, decoder: JSONDecoder) = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return (e, d)
    }()

    /// Up-to-4-entry rolling buffer. New readings append; older ones are
    /// dropped from the head when count exceeds 4.
    var vitalsLog: [SectionCReading] = []

    /// Append a snapshot of the current patient's vitals + AVPU. Skips if
    /// nothing has changed since the last entry (the engine fires on every
    /// processed sentence, not every reading). Returns true when a reading
    /// was actually appended, so the caller can persist only on change.
    @discardableResult
    private func appendVitalsSnapshot() -> Bool {
        guard let p = primaryPatient else { return false }
        let reading = SectionCReading(
            timestamp: Date(),
            vitals: p.vitals,
            avpu: p.march.consciousness
        )
        if let last = vitalsLog.last,
           last.vitals == reading.vitals,
           last.avpu == reading.avpu {
            return false
        }
        vitalsLog.append(reading)
        if vitalsLog.count > 4 {
            vitalsLog.removeFirst(vitalsLog.count - 4)
        }
        return true
    }

    /// Persist the §C rolling buffer to the active encounter dir so the
    /// DD1380 exporter is not dependent on ephemeral UI state and the grid
    /// survives crash recovery. App-layer only — `vitalsLog` is not part of
    /// `PatientState`, so this does not touch the event-sourcing invariant.
    private func persistSectionC() async {
        guard let store = encounterStore else { return }
        guard let data = try? Self.sectionCCodec.encoder.encode(vitalsLog) else { return }
        try? await store.saveSectionC(data)
    }

    func loadDemoTranscript(_ text: String) async {
        transcript.removeAll()
        transcriptLedger = TranscriptSegmentLedger()
        partialTranscript = ""
        var startMs = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            transcript.append(TranscriptLine(speaker: .medic, text: line))
            transcriptLedger.appendRaw(
                text: line,
                startMs: startMs,
                endMs: startMs + 1_000,
                backend: .demo,
                isFinal: true
            )
            startMs += 1_000
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

    var operatorCallsign: String = ""
    var operatorRole: String = ""
    var operatorUnit: String = "2/75 RGR"
    var operatorDeviceId: String = "EUD-441-C"

    /// Operator scope-of-practice tier. Default CMC (corpsman/medic) — the
    /// app's primary user. ASM/CLS picks up scope-limiting warnings; CPP
    /// has full discretion.
    var operatorTier: OperatorTier = .cmc

    var voiceCommandsEnabled: Bool = true
    var hapticFeedbackEnabled: Bool = true
    var lockOrientationEnabled: Bool = true
    var autoExportOnWiredHandoffEnabled: Bool = false

    func wipeSession() async {
        if encounterStore != nil {
            do {
                try await encounterStore?.purgeAll()
                let enc = documentsURL.appendingPathComponent("encounters")
                // PURGE gate: a failed delete must SURFACE to the operator, never crash a
                // field device (an assert() here SIGTRAPs debug/test builds). The runtime
                // check is the real gate; success is confirmed after re-arm below.
                if FileManager.default.fileExists(atPath: enc.path) {
                    appendSystem("WIPE INCOMPLETE · archive still present")
                }
            } catch {
                appendSystem("WIPE FAILED · \(error.localizedDescription)")
            }
        }
        // --- existing in-memory reset (verbatim) ---
        provisionalSettleTask?.cancel(); provisionalSettleTask = nil; provisionalLineId = nil
        // Cancelling provisionalEngineTask signals any suspended chained tasks to short-circuit
        // at their `if Task.isCancelled { return }` guards. The captured engine reference inside
        // those closures also ensures they cannot accidentally target the fresh engine assigned
        // below even if they had somehow already passed the cancellation check.
        provisionalEngineTask?.cancel(); provisionalEngineTask = nil
        voiceCommandTask?.cancel()
        voiceCommandTask = nil
        pendingVoiceCommand = nil
        transcript.removeAll()
        transcriptLedger = TranscriptSegmentLedger()
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
        vitalsLog.removeAll()
        lastMedevacTransmitTime = nil
        graniteReviewQueue.removeAll()
        lastConflictMessage = nil
        // Re-arm persistence (operator's continuous-persistence choice): the prior archive
        // is purged; open a FRESH empty casualty so post-WIPE care is crash-safe too. The
        // new casualty holds no patient data yet — OPSEC-clean (prior PHI is gone).
        persistedCursor = 0
        if encounterStore != nil {
            do {
                try await encounterStore?.startNewCasualty(
                    id: casualtyId, startUnix: Date().timeIntervalSince1970)
                await persistNewEvents()   // flush the fresh engine's lc-1 seed to disk
                appendSystem("WIPE COMPLETE · archive purged · \(casualtyId) ready")
            } catch {
                appendSystem("RE-ARM FAILED · \(error.localizedDescription)")
            }
        }
    }

    /// Begin a new casualty. Increments the casualty counter, wipes
    /// casualty-specific state, but preserves operator profile, theme, and
    /// RF discipline settings. Archives the prior casualty's record to disk
    /// before resetting so no encounter data is lost.
    func newPatient() async {
        let now = Date().timeIntervalSince1970
        await engine.recordLifecycle(.archived)
        await persistNewEvents()                                  // flush marker to OLD file
        try? await encounterStore?.archiveActive(endedUnix: now)  // manifest: old → archived
        // --- existing in-memory reset (verbatim), which sets a fresh engine + new casualtyId ---
        provisionalSettleTask?.cancel(); provisionalSettleTask = nil; provisionalLineId = nil
        provisionalEngineTask?.cancel(); provisionalEngineTask = nil
        voiceCommandTask?.cancel(); voiceCommandTask = nil; pendingVoiceCommand = nil
        let oldId = casualtyId
        casualtyCounter += 1
        casualtyId = String(format: "C-%02d", casualtyCounter)
        transcript.removeAll(); transcriptLedger = TranscriptSegmentLedger(); partialTranscript = ""
        recognitionError = nil; primaryPatient = nil; allPatients.removeAll(); sessionStart = Date()
        engine = PatientStateEngine.standard()
        lastRecordingURL = nil; encounterNarrative = nil; zmistNarrative = nil
        vitalsLog.removeAll(); lastMedevacTransmitTime = nil; graniteReviewQueue.removeAll(); lastConflictMessage = nil
        // --- open the new casualty on disk + flush its seed ---
        persistedCursor = 0
        try? await encounterStore?.startNewCasualty(id: casualtyId, startUnix: now)
        await persistNewEvents()                                  // flush new engine's lc-1 seed
        appendSystem("NEW CASUALTY · \(casualtyId) · \(oldId) archived")
    }

    /// Mark the current casualty's care as complete. Archives the record to
    /// disk before resetting, then clears casualty-specific state so the
    /// screen is ready for the next casualty (without incrementing the
    /// counter — the medic taps NEW CASUALTY in Settings when they have a
    /// new patient assigned).
    func endCurrentCare() async {
        let now = Date().timeIntervalSince1970
        await engine.recordLifecycle(.encounterEnded)
        await persistNewEvents()
        try? await encounterStore?.archiveActive(endedUnix: now)
        // --- existing in-memory reset (verbatim) ---
        provisionalSettleTask?.cancel(); provisionalSettleTask = nil; provisionalLineId = nil
        provisionalEngineTask?.cancel(); provisionalEngineTask = nil
        voiceCommandTask?.cancel(); voiceCommandTask = nil; pendingVoiceCommand = nil
        let endedId = casualtyId
        appendSystem("CARE ENDED · \(endedId) · handoff finalized")
        transcript.removeAll(where: { $0.speaker != .system || !$0.text.contains("CARE ENDED") })
        transcriptLedger = TranscriptSegmentLedger(); partialTranscript = ""
        primaryPatient = nil; allPatients.removeAll(); engine = PatientStateEngine.standard()
        lastRecordingURL = nil; encounterNarrative = nil; zmistNarrative = nil
        vitalsLog.removeAll(); lastMedevacTransmitTime = nil; graniteReviewQueue.removeAll(); lastConflictMessage = nil
        // End Care leaves a clean slate but keeps persistence live for the next casualty
        // under the same id: re-open a fresh dir + flush the new engine's seed.
        persistedCursor = 0
        try? await encounterStore?.startNewCasualty(id: casualtyId, startUnix: now)
        await persistNewEvents()
    }

    // MARK: - SLM-generated text (persists across screen switches)

    /// 2–3 sentence prose summary of the encounter. Set by the Generate
    /// Narrative button on Handoff. Cleared on lifecycle changes.
    var encounterNarrative: String?

    /// SLM-formatted ZMIST handoff block. Set by the Generate ZMIST button
    /// on Handoff. Cleared on lifecycle changes.
    var zmistNarrative: String?

    // MARK: - Voice commands (Task S3-7)

    /// Currently armed voice command, or nil. UI binds to this for the
    /// auto-fire banner. Set by `armVoiceCommand`, cleared by
    /// `cancelVoiceCommand` (scrim tap) or by the auto-fire 2s sleep
    /// completing.
    var pendingVoiceCommand: PendingVoiceCommand?

    /// In-flight auto-fire timer. Cancelled by `cancelVoiceCommand`,
    /// every fresh `armVoiceCommand`, and lifecycle actions
    /// (newPatient / endCurrentCare / wipeSession).
    var voiceCommandTask: Task<Void, Never>?

    // MARK: - Confirmation flow for lifecycle actions

    /// When non-nil, ContentView renders a top-positioned confirmation banner.
    /// Set by `requestConfirmation`, cleared by `confirm` or
    /// `cancelConfirmation`.
    var pendingConfirmation: ConfirmationAction?

    func requestConfirmation(_ action: ConfirmationAction) {
        pendingConfirmation = action
    }

    func confirmPending() async {
        guard let action = pendingConfirmation else { return }
        pendingConfirmation = nil
        switch action {
        case .newPatient: await newPatient()
        case .endCare:    await endCurrentCare()
        case .wipe:       await wipeSession()
        }
    }

    func cancelConfirmation() {
        pendingConfirmation = nil
    }

    // MARK: - 2026 sprint warnings (Tasks 2.4 + 2.5)

    /// Non-blocking warnings derived from the current patient state +
    /// operator tier. Surfaced as a banner on the TCCC Card screen.
    /// Empty when there's nothing to flag.
    var pendingWarnings: [TCCCWarning] {
        var out: [TCCCWarning] = []
        guard let patient = primaryPatient else { return out }

        // 2.4 — AVPU before ketamine.
        let hasKetamine = patient.interventions.contains { intervention in
            intervention.description.lowercased().contains("ketamine")
        } || (patient.paws.pain?.lowercased().contains("ketamine") ?? false)
        if hasKetamine && patient.march.consciousness == nil {
            out.append(.avpuBeforeKetamine)
        }

        // 2.5 — ASM/CLS TQ conversion beyond 2 hours.
        if operatorTier.isASMOrCLS,
           let conversion = patient.interventions.first(where: { $0.kind == .tourniquetConversion }),
           let application = patient.interventions.first(where: { $0.kind == .tourniquet }) {
            let elapsed = conversion.timestamp.timeIntervalSince(application.timestamp)
            if elapsed > 2 * 60 * 60 {
                out.append(.tqConversionScope)
            }
        }

        return out
    }
}

// MARK: - Voice commands (Task S3-7)

extension AppState {
    /// Phrases that map 1:1 to a destructive lifecycle action. Matched
    /// case-insensitively, word-boundary, against committed final text.
    /// Voice commands are deliberately phrase-rare so they don't fire
    /// from natural conversation.
    enum VoiceCommand: String, CaseIterable, Sendable, Hashable {
        case newPatient   = "new patient"
        case endEncounter = "end encounter"
    }

    /// A pending voice-command auto-fire. nil = no pending command.
    /// `firesAt` is when the action runs unless cancelled.
    struct PendingVoiceCommand: Equatable, Sendable {
        let command: VoiceCommand
        let firesAt: Date
    }

    /// Check whether the committed line contains a voice-command phrase.
    /// Returns the FIRST match (commands are mutually exclusive in any
    /// reasonable utterance — no need to scan further).
    func detectVoiceCommand(in text: String) -> VoiceCommand? {
        let lower = text.lowercased()
        for cmd in VoiceCommand.allCases {
            // Word-boundary match — "new patient is alert" matches,
            // but "newest patient" doesn't.
            let pattern = "\\b\(cmd.rawValue)\\b"
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return cmd
            }
        }
        return nil
    }

    /// Arm a voice-command auto-fire. Banner shows for 2s; tapping the
    /// scrim cancels. A newer arming cancels any prior arming.
    func armVoiceCommand(_ cmd: VoiceCommand) {
        // Voice commands are gated by the operator's Settings toggle.
        guard voiceCommandsEnabled else { return }
        voiceCommandTask?.cancel()
        let firesAt = Date().addingTimeInterval(2.0)
        pendingVoiceCommand = .init(command: cmd, firesAt: firesAt)
        voiceCommandTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // Guard against the case where the user cancelled or a different
            // command was armed during the sleep.
            guard self.pendingVoiceCommand?.command == cmd else { return }
            self.pendingVoiceCommand = nil
            switch cmd {
            case .newPatient:   await self.newPatient()
            case .endEncounter: await self.endCurrentCare()
            }
        }
    }

    /// Cancel any pending voice-command auto-fire. Used by the banner's
    /// tap-to-cancel scrim and by lifecycle actions that supersede the
    /// pending command.
    func cancelVoiceCommand() {
        voiceCommandTask?.cancel()
        voiceCommandTask = nil
        pendingVoiceCommand = nil
    }
}

// MARK: - LLM backend dispatch

extension AppState {
    /// The active backend for this AppState's `llmBackend` selection.
    /// Recomputed on each access — backends are stateless wrappers and
    /// the four generators take a backend per call, so allocation cost
    /// is negligible. This is the single decode site for the runtime
    /// LLM choice; everything else (RadioScriptGenerator,
    /// ZMISTNarrativeGenerator, EncounterNarrativeGenerator)
    /// consumes the protocol existential.
    var currentBackend: any TCCCLLMBackend {
        switch llmBackend {
        case .appleFoundation: AppleFoundationLLMBackend()
        case .lfm2:            LFM2LLMBackend()
        case .qwen3:           QwenLLMBackend()
        case .graniteText:     GraniteTextLLMBackend()
        }
    }
}
