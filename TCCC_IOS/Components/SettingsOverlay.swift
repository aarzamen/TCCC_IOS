import SwiftUI
import TCCCAudio
import UniformTypeIdentifiers

struct SettingsOverlay: View {
    let state: AppState
    @Environment(\.palette) private var palette

    @State private var wipeProgress: CGFloat = 0
    @State private var wipeTask: Task<Void, Never>?
    private let wipeDuration: Double = 3.0

    /// Granite Speech Foundation Sprint 1 v3 §G1: file-importer
    /// presentation toggle for "Select Granite Speech Model Folder".
    /// Local UI state — the persistent bookmark itself lives in
    /// `state.graniteSpeechBookmarkStore`.
    @State private var graniteSpeechPickerOpen: Bool = false
    /// Bumped after a successful pick or a clear-bookmark action so
    /// `graniteSpeechBookmarkStatus` re-evaluates. UserDefaults reads
    /// don't trigger SwiftUI invalidation on their own.
    @State private var graniteSpeechStatusRevision: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            palette.bg.opacity(0.0)
                .ignoresSafeArea()

            scrim

            sheet
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var scrim: some View {
        Color.black.opacity(0.72)
            .ignoresSafeArea()
            .onTapGesture {
                state.settingsOpen = false
            }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    displayModeSection
                    sectionDivider
                    audioASRSection
                    sectionDivider
                    llmBackendSection
                    sectionDivider
                    systemSection
                    sectionDivider
                    operatorSection
                    sectionDivider
                    sessionSection
                }
            }
        }
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .strokeBorder(palette.lineStrong, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text("Settings")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(palette.fg2)

            Spacer(minLength: 0)

            Button {
                state.settingsOpen = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("Close")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.6)
                        .textCase(.uppercase)
                }
                .foregroundStyle(palette.fg)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .overlay(
                    Rectangle()
                        .strokeBorder(palette.line, lineWidth: Layout.hairline)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.lineStrong)
                .frame(height: Layout.hairline)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(height: Layout.hairline)
    }

    // MARK: - Display Mode

    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Mode")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)

            VStack(spacing: 6) {
                ForEach(Theme.allCases) { theme in
                    ThemeOptCard(theme: theme, isSelected: state.theme == theme) {
                        state.theme = theme
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Audio + ASR (night-pass full-tilt Parakeet)

    private var audioASRSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audio · ASR")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)

            // ── Backend radio ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Backend")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)

                ForEach(AppState.ASRBackend.allCases) { backend in
                    asrBackendRow(backend)
                }

                if state.asrBackend == .parakeet {
                    parakeetStatusRow
                        .padding(.top, 4)
                }

                if state.asrBackend == .graniteSpeech {
                    graniteSpeechModelFolderRow
                        .padding(.top, 4)
                }
            }

            // ── Mic gain slider ────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Microphone Gain")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Text(String(format: "%+.1f dB", state.audioGainDb))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.fg)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { state.audioGainDb },
                        set: { state.audioGainDb = $0 }
                    ),
                    in: -20.0...20.0,
                    step: 0.5
                )
                HStack {
                    Text("-20 dB · quiet")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.fg3)
                    Spacer(minLength: 0)
                    Button("Reset") {
                        state.audioGainDb = 0
                    }
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.fg2)
                    Spacer(minLength: 0)
                    Text("+20 dB · loud")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.fg3)
                }
            }
        }
        .padding(16)
    }

    private func asrBackendRow(_ backend: AppState.ASRBackend) -> some View {
        let isSelected = state.asrBackend == backend
        return Button {
            Haptics.selection()
            state.asrBackend = backend
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? palette.accent : palette.fg2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.fg)
                    Text(asrBackendSubtitle(backend))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.fg3)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? palette.bg2 : Color.clear)
            .overlay(
                Rectangle()
                    .strokeBorder(isSelected ? palette.accent : palette.line, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private func asrBackendSubtitle(_ backend: AppState.ASRBackend) -> String {
        switch backend {
        case .appleSpeech:
            "On-device · default · always available"
        case .parakeet:
            "On-device · NVIDIA Parakeet TDT 0.6B · English only"
        case .graniteSpeech:
            "On-device · IBM Granite Speech 4.0 1B 5-bit · pick model folder below"
        }
    }

    private var parakeetStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(parakeetStatusColor)
                .frame(width: 8, height: 8)
            Text(parakeetStatusLabel)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if shouldShowDownloadButton {
                Button {
                    state.beginParakeetDownload()
                } label: {
                    Text("Download · ~300 MB")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.accent)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .overlay(
                            Rectangle()
                                .strokeBorder(palette.accent, lineWidth: Layout.hairline)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(palette.bg2)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    private var parakeetStatusLabel: String {
        switch state.parakeetStatus {
        case .unknown:        return "Status unknown — tap Download to fetch"
        case .notDownloaded:  return "Not downloaded"
        case .downloading(let f):
            return "Downloading · \(Int(f * 100))%"
        case .ready:          return "Cached · ready"
        case .failed(let msg): return "Failed · \(msg)"
        }
    }

    private var parakeetStatusColor: Color {
        switch state.parakeetStatus {
        case .ready:                 return palette.ok
        case .downloading:           return palette.warn
        case .failed:                return palette.crit
        case .notDownloaded, .unknown: return palette.fg3
        }
    }

    private var shouldShowDownloadButton: Bool {
        switch state.parakeetStatus {
        case .unknown, .notDownloaded, .failed: return true
        case .downloading, .ready:              return false
        }
    }

    // MARK: - Granite Speech model folder (Sprint 1 v3 §G1)

    private enum GraniteSpeechBookmarkUIStatus {
        case noBookmark
        case active(folderName: String)
        case stale(folderName: String)
        case error(message: String)

        /// True when bookmark data exists in UserDefaults — even if it
        /// fails to resolve. Drives whether the row shows "Re-select"
        /// + Clear (any picked state) vs the initial "Select Model
        /// Folder" CTA (`.noBookmark` only).
        var isPicked: Bool {
            switch self {
            case .noBookmark:                return false
            case .active, .stale, .error:    return true
            }
        }
    }

    private func graniteSpeechBookmarkStatus() -> GraniteSpeechBookmarkUIStatus {
        // Touch the revision so SwiftUI re-evaluates after a pick.
        _ = graniteSpeechStatusRevision
        do {
            let (url, isStale) = try state.graniteSpeechBookmarkStore.resolve()
            let name = url.lastPathComponent
            return isStale ? .stale(folderName: name) : .active(folderName: name)
        } catch GraniteSpeechBookmarkError.noBookmarkSaved {
            return .noBookmark
        } catch {
            return .error(message: error.localizedDescription)
        }
    }

    private var graniteSpeechModelFolderRow: some View {
        let status = graniteSpeechBookmarkStatus()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(graniteSpeechStatusColor(status))
                    .frame(width: 8, height: 8)
                Text(graniteSpeechStatusLabel(status))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    graniteSpeechPickerOpen = true
                } label: {
                    Text(status.isPicked ? "Re-select Model Folder" : "Select Model Folder")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.accent)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Rectangle()
                                .strokeBorder(palette.accent, lineWidth: Layout.hairline)
                        )
                }
                .buttonStyle(.plain)

                if status.isPicked {
                    Button {
                        state.graniteSpeechBookmarkStore.clear()
                        graniteSpeechStatusRevision &+= 1
                    } label: {
                        Text("Clear")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(palette.fg2)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(palette.bg2)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
        .fileImporter(
            isPresented: $graniteSpeechPickerOpen,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleGraniteSpeechPick(result)
        }
    }

    private func handleGraniteSpeechPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // The picker URL carries an implicit security scope.
            // Activate it briefly so `bookmarkData` succeeds, then
            // release. The runtime re-activates scope on prime().
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                try state.graniteSpeechBookmarkStore.save(url: url)
                graniteSpeechStatusRevision &+= 1
            } catch {
                // Surface the failure inline by setting the status
                // revision; on next render `graniteSpeechBookmarkStatus`
                // will see no bookmark and report `.noBookmark`.
                graniteSpeechStatusRevision &+= 1
            }
        case .failure:
            // Picker dismissed or failed — no state change.
            break
        }
    }

    private func graniteSpeechStatusLabel(_ status: GraniteSpeechBookmarkUIStatus) -> String {
        switch status {
        case .noBookmark:               return "No model folder selected"
        case .active(let name):         return "Active · \(name)"
        case .stale(let name):          return "Stale · re-select \(name)"
        case .error(let message):       return "Error · \(message)"
        }
    }

    private func graniteSpeechStatusColor(_ status: GraniteSpeechBookmarkUIStatus) -> Color {
        switch status {
        case .active:     return palette.ok
        case .stale:      return palette.warn
        case .error:      return palette.crit
        case .noBookmark: return palette.fg3
        }
    }

    // MARK: - LLM Backend (B3)
    //
    // Symmetric to the ASR backend section above. Three radio cards —
    // Apple Foundation Models (default, real), Liquid LFM2.5 1.2B (alt,
    // on ice), Qwen 3 1.7B (alt, on ice). Each row reads its backend's
    // `availability` and renders a status pill. LFM2 + Qwen currently
    // return `.modelNotProvided` from their stubs; they're still
    // selectable so the operator can see "NOT PROVIDED" intentionally
    // (and the four generators will later refuse to run rather than
    // silently fall back).

    private var llmBackendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LLM · Backend")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(AppState.LLMBackend.allCases) { backend in
                    LLMBackendRow(
                        backend: backend,
                        isSelected: state.llmBackend == backend,
                        isDownloading: state.downloadingBackend == backend,
                        onTap: {
                            Haptics.selection()
                            state.llmBackend = backend
                        },
                        onDownload: {
                            Task { await state.downloadBackendWeights(backend) }
                        }
                    )
                }
            }

            Text("Apple Foundation Models is the runtime default. Alt backends require an explicit Settings download before generation. Granite is for hot-seat patch review, not direct state mutation.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.fg3)
                .lineLimit(3)
        }
        .padding(16)
    }

    // MARK: - System

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("System")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)
                .padding(.bottom, 8)

            ToggleRow(label: "Voice Commands", detail: nil, isOn: Binding(get: { state.voiceCommandsEnabled }, set: { state.voiceCommandsEnabled = $0 }))
            ToggleRow(label: "Haptic Feedback", detail: nil, isOn: Binding(get: { state.hapticFeedbackEnabled }, set: { state.hapticFeedbackEnabled = $0 }))
            ToggleRow(label: "Lock Orientation (Landscape)", detail: nil, isOn: Binding(get: { state.lockOrientationEnabled }, set: { state.lockOrientationEnabled = $0 }))
            ToggleRow(label: "Auto-Export on Wired Handoff", detail: nil, isOn: Binding(get: { state.autoExportOnWiredHandoffEnabled }, set: { state.autoExportOnWiredHandoffEnabled = $0 }))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Operator

    private var operatorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operator")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                editableField(
                    label: "Callsign",
                    binding: Binding(get: { state.operatorCallsign }, set: { state.operatorCallsign = $0 }),
                    keyboard: .asciiCapable,
                    autoCap: .characters
                )
                editableField(
                    label: "Role",
                    binding: Binding(get: { state.operatorRole }, set: { state.operatorRole = $0 }),
                    keyboard: .asciiCapable,
                    autoCap: .characters
                )
                editableField(
                    label: "Unit",
                    binding: Binding(get: { state.operatorUnit }, set: { state.operatorUnit = $0 }),
                    keyboard: .asciiCapable,
                    autoCap: .characters
                )
                Field(label: "Device ID", value: state.operatorDeviceId)
            }

            tierPickerBlock
        }
        .padding(16)
    }

    /// Operator-tier picker. `OperatorTier` is a controlled vocabulary
    /// (ASM / CLS / CMC / CPP) and drives scope-of-practice warnings;
    /// a segmented picker is the right input affordance.
    @ViewBuilder
    private var tierPickerBlock: some View {
        Text("Tier")
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.6)
            .foregroundStyle(palette.fg2)
            .textCase(.uppercase)
            .padding(.top, 6)

        Picker("Tier", selection: Binding(
            get: { state.operatorTier },
            set: { state.operatorTier = $0 }
        )) {
            ForEach(AppState.OperatorTier.allCases, id: \.self) { tier in
                Text(tier.rawValue).tag(tier)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Visual twin of `Field` (the read-only label/value tile) but
    /// hosts an inline `TextField` so the operator can update their
    /// profile from Settings. Border + label styling deliberately
    /// match `Field.swift` so the section reads as one block.
    private func editableField(
        label: String,
        binding: Binding<String>,
        keyboard: UIKeyboardType,
        autoCap: TextInputAutocapitalization
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            TextField("", text: binding)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autoCap)
                .autocorrectionDisabled(true)
                .textFieldStyle(.plain)
                .submitLabel(.done)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    // Location is captured on the MEDEVAC screen via USE GPS FIX (real
    // CoreLocation one-shot). The former Settings location-source picker
    // (manual lat/lon + demo Bagram seed) was removed — no manual/demo
    // grid entry exists in production UI.

    // MARK: - Session

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(palette.crit)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                // A3 — NEW CAS clears transcript, primaryPatient, allPatients,
                // vitalsLog, and the narrative cache. CLAUDE.md hard constraint
                // #4 forbids single-tap destructive actions; 2s hold matches
                // the TRANSMIT pattern (WIPE uses 3s, justified below).
                HoldToConfirmButton(
                    label: "New Cas",
                    systemImage: "person.crop.circle.badge.plus",
                    style: .standard,
                    holdSeconds: 2.0
                ) {
                    Task { @MainActor in await state.newPatient() }
                    state.settingsOpen = false
                }

                ZStack(alignment: .bottomLeading) {
                    BigButton(
                        "Wipe",
                        systemImage: "trash.fill",
                        style: .accent,
                        action: {}
                    )
                    .gesture(wipeHoldGesture)

                    Rectangle()
                        .fill(palette.crit)
                        .frame(width: wipeProgress * 200, height: 2)
                        .opacity(wipeProgress > 0 ? 1 : 0)
                }
            }

            Text("All session data is encrypted at rest (AES-256). Wipe is irrecoverable.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.fg3)
                .lineLimit(2)
        }
        .padding(16)
    }

    private var wipeHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if wipeTask == nil {
                    wipeProgress = 0
                    let start = Date()
                    wipeTask = Task { @MainActor in
                        while !Task.isCancelled {
                            let elapsed = Date().timeIntervalSince(start)
                            let p = min(1, elapsed / wipeDuration)
                            wipeProgress = CGFloat(p)
                            if p >= 1 {
                                await state.wipeSession()
                                state.appendSystem("SESSION WIPED · \(Self.timestamp())")
                                wipeProgress = 0
                                wipeTask = nil
                                state.settingsOpen = false
                                return
                            }
                            try? await Task.sleep(nanoseconds: 30_000_000)
                        }
                    }
                }
            }
            .onEnded { _ in
                wipeTask?.cancel()
                wipeTask = nil
                if wipeProgress < 1 {
                    withAnimation(.fast) {
                        wipeProgress = 0
                    }
                }
            }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

// MARK: - LLMBackendRow (B3)

/// One radio card in the LLM Backend picker. Owns its own
/// `BackendAvailability` state so we can read it async without
/// blocking the parent view's render. The row mirrors the visual
/// shape of `asrBackendRow` in `SettingsOverlay`.
private struct LLMBackendRow: View {
    let backend: AppState.LLMBackend
    let isSelected: Bool
    let isDownloading: Bool
    let onTap: () -> Void
    let onDownload: () -> Void

    @Environment(\.palette) private var palette
    @State private var availability: BackendAvailability = .unknown

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? palette.accent : palette.fg2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backend.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.fg)
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.fg3)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    downloadAffordance
                    statusPill
                }
                if let warning = downloadWarning {
                    Text(warning)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(palette.fg3)
                        .padding(.leading, 24)  // align under display name
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? palette.bg2 : Color.clear)
            .overlay(
                Rectangle()
                    .strokeBorder(isSelected ? palette.accent : palette.line, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
        .task(id: backend) {
            availability = await Self.readAvailability(for: backend)
        }
        .task(id: isDownloading) {
            // When a download finishes (isDownloading flips back to false),
            // re-read availability so the status pill flips READY without
            // needing the operator to leave + re-open Settings.
            if !isDownloading {
                availability = await Self.readAvailability(for: backend)
            }
        }
    }

    /// DOWNLOAD button (or a spinner if a fetch is in flight). Only shown
    /// for non-Apple backends whose weights aren't on disk yet.
    @ViewBuilder
    private var downloadAffordance: some View {
        if backend != .appleFoundation && availability == .modelNotProvided {
            if isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 4)
            } else {
                Button(action: onDownload) {
                    Text("DOWNLOAD")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            Rectangle()
                                .strokeBorder(palette.accent, lineWidth: Layout.hairline)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One-line size warning rendered under the row when the DOWNLOAD
    /// button is visible. RF Ghost: download is the only intentional
    /// network call the app makes; surface the cost up front.
    private var downloadWarning: String? {
        guard backend != .appleFoundation, availability == .modelNotProvided else {
            return nil
        }
        switch backend {
        case .appleFoundation: return nil
        case .lfm2:            return "Wi-Fi · 660 MB on first download"
        case .qwen3:           return "Wi-Fi · 968 MB on first download"
        case .graniteText:     return "Wi-Fi · 823 MB model on first download"
        }
    }

    private var subtitle: String {
        switch backend {
        case .appleFoundation:
            "On-device · default · ships with iOS 26 on eligible devices"
        case .lfm2:
            "On-device · LFM Open License · model weights not bundled"
        case .qwen3:
            "On-device · Apache-2.0 · model weights not bundled"
        case .graniteText:
            "On-device · Apache-2.0 · hot-seat JSON backend"
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let (label, fg) = pillContent
        Text(label)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(fg)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .overlay(
                Rectangle()
                    .strokeBorder(fg.opacity(0.6), lineWidth: Layout.hairline)
            )
    }

    private var pillContent: (String, Color) {
        switch availability {
        case .available:         ("READY", palette.ok)
        case .downloading:       ("DOWNLOADING", palette.warn)
        case .modelNotProvided:  ("NOT PROVIDED", palette.fg3)
        case .deviceNotEligible: ("INELIGIBLE", palette.crit)
        case .disabled:          ("DISABLED", palette.fg3)
        case .unknown:           ("UNKNOWN", palette.fg3)
        }
    }

    /// Construct a fresh backend instance and read its availability.
    /// Backends are stateless wrappers — instantiation is cheap and
    /// matches the pattern AppState's future `currentBackend` (Task B2)
    /// would use.
    private static func readAvailability(for backend: AppState.LLMBackend) async -> BackendAvailability {
        switch backend {
        case .appleFoundation:
            return await AppleFoundationLLMBackend().availability
        case .lfm2:
            return await LFM2LLMBackend().availability
        case .qwen3:
            return await QwenLLMBackend().availability
        case .graniteText:
            return await GraniteTextLLMBackend().availability
        }
    }
}
