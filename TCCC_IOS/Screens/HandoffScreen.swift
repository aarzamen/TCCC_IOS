import SwiftUI
import TCCCDomain

/// Screen 05 — Role-1 → Role-2 Handoff.
///
/// Three-column layout per design brief §5.5:
///   1.1fr  ENCOUNTER SUMMARY (rolled-up state lines)
///   1.0fr  TIMELINE          (vertical chronological events with rail + node)
///   0.9fr  EXPORT · TRANSMIT (export cards + 2×2 destination grid + AES TRANSMIT)
///
/// The TRANSMIT button uses a 2-second `LongPressGesture` with a visual
/// progress bar; on completion it appends a system transcript line. No
/// networking framework is wired (RF Ghost). When the QR destination is
/// active, completion also raises a sheet rendering an offline `CIQRCodeGenerator`
/// QR of the patient's JSON-encoded state.
struct HandoffScreen: View {
    let state: AppState

    @Environment(\.palette) private var palette
    @State private var transmitProgress: Double = 0
    @State private var isTransmitting: Bool = false
    @State private var elapsedTick: Date = Date()

    private var patient: PatientState? { state.primaryPatient }

    private static let tickInterval: TimeInterval = 1
    private let timer = Timer.publish(every: HandoffScreen.tickInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .handoff,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "DESTINATION",
                trailingKickerValue: state.selectedHandoffDestination.displayName
            )

            HStack(spacing: Layout.gridGap) {
                summaryColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1.1)

                timelineColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1.0)

                exportColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0.9)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(
                leadingLabel: "MEDEVAC",
                trailingLabel: nil,
                onSettings: { state.settingsOpen = true },
                onQuickActions: { state.quickActionsOpen = true }
            )
        }
        .background(palette.bg)
        .onReceive(timer) { _ in elapsedTick = Date() }
        .sheet(isPresented: Binding(
            get: { state.qrOverlayVisible },
            set: { state.qrOverlayVisible = $0 }
        )) {
            QRSheet(payload: HandoffQR.payload(for: patient))
                .environment(\.palette, palette)
        }
    }

    // MARK: - Column 1: Encounter Summary

    private var summaryColumn: some View {
        Panel(
            "Encounter Summary",
            titleIcon: "doc.text",
            action: state.casualtyId,
            padded: false
        ) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(HandoffSummary.lines(for: patient, casualtyId: state.casualtyId)) { line in
                            SumLineView(
                                icon: line.icon,
                                label: line.label,
                                value: line.value,
                                isHot: line.isHot
                            )
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: Layout.hairline)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)

                summaryFooter
            }
        }
    }

    private var summaryFooter: some View {
        Text("AI-GENERATED · MEDIC TO VERIFY BEFORE TRANSMIT")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(palette.fg3)
            .textCase(.uppercase)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
    }

    // MARK: - Column 2: Timeline

    private var timelineColumn: some View {
        Panel(
            "Timeline",
            titleIcon: "clock",
            action: HandoffTimeline.formatElapsed(from: state.sessionStart, to: elapsedTick),
            padded: false
        ) {
            ScrollView {
                let events = HandoffTimeline.events(for: patient, sessionStart: state.sessionStart, now: elapsedTick)
                LazyVStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                        TimelineRow(
                            timestamp: HandoffTimeline.formatTimestamp(event.timestamp),
                            icon: event.icon,
                            kindLabel: event.kindLabel,
                            detail: event.detail,
                            isHot: event.isHot,
                            isLast: idx == events.count - 1
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Column 3: Export · Transmit

    private var exportColumn: some View {
        Panel("Export · Transmit", titleIcon: "square.and.arrow.up", padded: false) {
            VStack(spacing: 0) {
                exportCardsBlock
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)

                destinationLabel
                    .padding(.horizontal, 12)
                destinationGrid
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                Spacer(minLength: 8)

                transmitButtonBlock
                    .padding(.horizontal, 12)

                transmitFooter
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var exportCardsBlock: some View {
        VStack(spacing: 6) {
            ExportCard(
                icon: "doc.richtext",
                title: "DD-1380 PDF",
                detail: "Pending PDFKit",
                isReady: false
            )
            ExportCard(
                icon: "curlybraces",
                title: "JSON Encounter",
                detail: "\(HandoffQR.payloadKilobytes(for: patient)) KB",
                isReady: patient != nil
            )
            ExportCard(
                icon: "waveform",
                title: "Audio + Transcript",
                detail: audioStatusDetail,
                isReady: !state.transcript.isEmpty
            )
            ExportCard(
                icon: "tablecells",
                title: "Vitals CSV",
                detail: vitalsCsvDetail,
                isReady: vitalsFieldCount > 0
            )
        }
    }

    private var destinationLabel: some View {
        Text("Destination")
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(palette.fg2)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationGrid: some View {
        let cols = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(HandoffDestination.allCases, id: \.self) { dest in
                DestCard(
                    icon: dest.symbol,
                    label: dest.displayName,
                    isActive: state.selectedHandoffDestination == dest,
                    action: { state.selectedHandoffDestination = dest }
                )
            }
        }
    }

    private var transmitButtonBlock: some View {
        ZStack(alignment: .bottomLeading) {
            BigButton(
                "Transmit / Hold 2s · AES-256",
                systemImage: "antenna.radiowaves.left.and.right",
                style: .accent
            ) { /* handled by long-press gesture below */ }
                .gesture(
                    LongPressGesture(minimumDuration: 2, maximumDistance: 30)
                        .onChanged { _ in
                            if !isTransmitting {
                                isTransmitting = true
                                withAnimation(.linear(duration: 2)) {
                                    transmitProgress = 1.0
                                }
                            }
                        }
                        .onEnded { _ in
                            completeTransmit()
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            if isTransmitting && transmitProgress < 1 {
                                cancelTransmit()
                            }
                        }
                )

            // Progress bar — thin line growing along the bottom of the button.
            GeometryReader { geo in
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: geo.size.width * transmitProgress, height: 2)
            }
            .frame(height: 2)
            .allowsHitTesting(false)
        }
    }

    private var transmitFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.fg3)
            Text("AIRGAP · QR FALLBACK")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(palette.fg3)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived export details

    private var audioStatusDetail: String {
        let lines = state.transcript.count
        if lines == 0 { return "Capture in progress" }
        return "\(lines) lines logged"
    }

    private var vitalsFieldCount: Int {
        guard let v = patient?.vitals else { return 0 }
        var n = 0
        if v.hr != nil { n += 1 }
        if v.bp != nil { n += 1 }
        if v.spo2 != nil { n += 1 }
        if v.rr != nil { n += 1 }
        if v.gcs != nil { n += 1 }
        if v.temperatureCelsius != nil { n += 1 }
        if v.capillaryRefillSeconds != nil { n += 1 }
        return n
    }

    private var vitalsCsvDetail: String {
        let n = vitalsFieldCount
        if n == 0 { return "No vitals recorded" }
        return "\(n) field\(n == 1 ? "" : "s")"
    }

    // MARK: - Transmit gesture handling

    private func completeTransmit() {
        guard isTransmitting else { return }
        isTransmitting = false
        transmitProgress = 1
        let dest = state.selectedHandoffDestination
        let stamp = HandoffSummary.formatTime(Date())
        state.appendSystem("TRANSMIT · \(dest.displayName) · \(stamp)")
        if dest == .qr {
            state.qrOverlayVisible = true
        }
        // Reset progress shortly after completion so the button is reusable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                transmitProgress = 0
            }
        }
    }

    private func cancelTransmit() {
        isTransmitting = false
        withAnimation(.easeOut(duration: 0.15)) {
            transmitProgress = 0
        }
    }
}

// MARK: - QR sheet

/// Modal sheet showing the offline QR code for the selected payload.
private struct QRSheet: View {
    let payload: Data

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            palette.bg
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text("OFFLINE QR · ROLE-2 SCAN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(palette.fg)
                        .textCase(.uppercase)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.fg)
                            .padding(8)
                            .frame(minWidth: Layout.minHitTarget, minHeight: Layout.minHitTarget)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 14)

                GeometryReader { geo in
                    let side = min(min(geo.size.width, geo.size.height), 360)
                    ZStack {
                        Rectangle()
                            .fill(palette.fg)
                        if let cg = HandoffQR.generateImage(from: payload) {
                            Image(decorative: cg, scale: 1, orientation: .up)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                        } else {
                            Text("QR unavailable")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.bg)
                        }
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Text("\(payload.count) bytes · AES-encrypted at rest")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg2)
                    .padding(.bottom, 14)
            }
            .padding(.top, 14)
        }
    }
}
