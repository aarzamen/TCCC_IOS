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
        }
        .padding(16)
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
