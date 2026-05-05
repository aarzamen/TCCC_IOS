import SwiftUI

struct SettingsOverlay: View {
    let state: AppState
    @Environment(\.palette) private var palette

    @State private var wipeProgress: CGFloat = 0
    @State private var wipeTask: Task<Void, Never>?
    private let wipeDuration: Double = 3.0

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
                    rfSection
                    sectionDivider
                    displayModeSection
                    sectionDivider
                    audioASRSection
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

    // MARK: - RF Discipline

    private var rfSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RF · Emissions Discipline")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                statusPill
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                spacing: 6
            ) {
                RFRow(name: "Wi-Fi", band: "2.4 / 5 GHz", icon: "wifi.slash")
                RFRow(name: "Bluetooth", band: "2.4 GHz", icon: "minus.diamond")
                RFRow(name: "Cellular", band: "Multi-band", icon: "antenna.radiowaves.left.and.right.slash")
                RFRow(name: "UWB", band: "6.5 / 8 GHz", icon: "wave.3.right")
                RFRow(name: "NFC", band: "13.56 MHz", icon: "wave.3.right.circle")
            }

            Text("Permitted Egress · Local Only")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
                .padding(.top, 4)

            HStack(spacing: 6) {
                EgressRow(name: "ANT+ Burst", band: "2.457 GHz · paired-only", icon: "dot.radiowaves.up.forward", state: state.antPlusArmed ? .armed : .disabled)
                EgressRow(name: "Jetson Link", band: "Local · paired-only", icon: "cpu", state: state.jetsonLinkArmed ? .armed : .disabled)
                EgressRow(name: "USB-C Wired", band: "MFi · primary handoff", icon: "bolt.horizontal.fill", state: state.usbConnected ? .connected : .armed)
            }

            Text("Hardware-disabled and signed-locked at all times during operational use. Status reflects the current MDM profile and can not be toggled from this screen.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.fg3)
                .lineLimit(3)
                .padding(.top, 6)
        }
        .padding(16)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(palette.accent)
                .frame(width: 6, height: 6)
            Text("RF Ghost · Confirmed")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .overlay(
            Rectangle()
                .strokeBorder(palette.accentDim, lineWidth: Layout.hairline)
        )
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
            ToggleRow(label: "Screen Burn Protection", detail: nil, isOn: Binding(get: { state.screenBurnProtectionEnabled }, set: { state.screenBurnProtectionEnabled = $0 }))
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
                Field(label: "Callsign", value: state.operatorCallsign)
                Field(label: "Role", value: state.operatorRole)
                Field(label: "Unit", value: state.operatorUnit)
                Field(label: "Device ID", value: state.operatorDeviceId)
            }

            locationSourceBlock
        }
        .padding(16)
    }

    /// A1 hardening — explicit picker over `AppState.LocationSource`.
    /// `none` is the safe default; `manual` exposes lat/lon TextFields;
    /// `demo` seeds the historical Bagram-area training coordinates so
    /// the demo path still works without lying to the radio script.
    @ViewBuilder
    private var locationSourceBlock: some View {
        Text("Location Source")
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.6)
            .foregroundStyle(palette.fg2)
            .textCase(.uppercase)
            .padding(.top, 6)

        Picker("Location Source", selection: locationSourceBinding) {
            ForEach(AppState.LocationSource.allCases) { src in
                Text(src.badge).tag(src)
            }
        }
        .pickerStyle(.segmented)

        if state.locationFix.source == .manual {
            HStack(spacing: 6) {
                manualField(label: "LAT", binding: latitudeBinding)
                manualField(label: "LON", binding: longitudeBinding)
            }
        } else if state.locationFix.source == .demo {
            Text("Demo coords: 34.5267, 69.1729 (training only — flagged DEMO on 9-line)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.warn)
        } else {
            Text("No fix — 9-line LINE 1 will render UNVERIFIED.")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.crit)
        }
    }

    private var locationSourceBinding: Binding<AppState.LocationSource> {
        Binding(
            get: { state.locationFix.source },
            set: { newSource in
                switch newSource {
                case .none:
                    state.locationFix = .init(source: .none, latitude: nil, longitude: nil)
                case .demo:
                    // Same Bagram-area coords as the legacy hardcoded
                    // default — but now explicitly labeled DEMO.
                    state.locationFix = .init(source: .demo, latitude: 34.5267, longitude: 69.1729)
                case .manual:
                    // Preserve any prior coords if switching from .demo;
                    // otherwise start blank and let operator type values.
                    let lat = state.locationFix.latitude
                    let lon = state.locationFix.longitude
                    state.locationFix = .init(source: .manual, latitude: lat, longitude: lon)
                }
            }
        )
    }

    private var latitudeBinding: Binding<String> {
        Binding(
            get: { state.locationFix.latitude.map { String($0) } ?? "" },
            set: { state.locationFix.latitude = Double($0) }
        )
    }

    private var longitudeBinding: Binding<String> {
        Binding(
            get: { state.locationFix.longitude.map { String($0) } ?? "" },
            set: { state.locationFix.longitude = Double($0) }
        )
    }

    private func manualField(label: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            TextField("", text: binding)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    // MARK: - Session

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(palette.crit)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                BigButton(
                    "New Cas",
                    systemImage: "person.crop.circle.badge.plus",
                    style: .standard
                ) {
                    state.newPatient()
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
                                state.wipeSession()
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
