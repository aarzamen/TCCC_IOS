import SwiftUI
import UIKit
import FoundationModels
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
    @State private var shareItems: [Any] = []
    @State private var shareSheetVisible: Bool = false

    @State private var narrativeGenerator = EncounterNarrativeGenerator()
    @State private var zmistGenerator = ZMISTNarrativeGenerator()
    @State private var isGeneratingNarrative: Bool = false
    @State private var isGeneratingZMIST: Bool = false
    @State private var slmError: String?

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

            GeometryReader { geo in
                let totalGap = Layout.gridGap * 2
                let usable = geo.size.width - totalGap
                // Layout playground: summary / timeline / export = 2.00 / 1.00 / 1.10
                let total: CGFloat = 4.10
                let w1 = usable * (2.00 / total)
                let w2 = usable * (1.00 / total)
                let w3 = usable - w1 - w2
                HStack(spacing: Layout.gridGap) {
                    summaryColumn
                        .frame(width: w1, height: geo.size.height)
                    timelineColumn
                        .frame(width: w2, height: geo.size.height)
                    exportColumn
                        .frame(width: w3, height: geo.size.height)
                }
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(
                state: state,
                leadingLabel: "MEDEVAC",
                trailingLabel: nil
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
        .sheet(isPresented: $shareSheetVisible) {
            ShareSheet(items: shareItems, onDismiss: { shareSheetVisible = false })
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
                    VStack(alignment: .leading, spacing: 0) {
                        if let narrative = state.encounterNarrative, !narrative.isEmpty {
                            slmBlock(label: "Narrative", body: narrative)
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: Layout.hairline)
                        }
                        if let zmist = state.zmistNarrative, !zmist.isEmpty {
                            slmBlock(label: "ZMIST", body: zmist, mono: true)
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: Layout.hairline)
                        }
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

                slmActionRow

                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)

                summaryFooter
            }
        }
    }

    private func slmBlock(label: String, body: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
            Text(body)
                .font(mono
                    ? .system(size: 12, weight: .medium, design: .monospaced)
                    : .system(size: 13, weight: .medium))
                .foregroundStyle(palette.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg2)
    }

    private var slmActionRow: some View {
        HStack(spacing: 6) {
            slmButton(
                title: state.encounterNarrative == nil ? "Narrative" : "Regen",
                icon: "wand.and.stars",
                isLoading: isGeneratingNarrative,
                action: handleGenerateNarrative
            )
            slmButton(
                title: state.zmistNarrative == nil ? "ZMIST" : "Regen Z",
                icon: "doc.text.fill",
                isLoading: isGeneratingZMIST,
                action: handleGenerateZMIST
            )
            if state.encounterNarrative != nil || state.zmistNarrative != nil {
                Button {
                    state.encounterNarrative = nil
                    state.zmistNarrative = nil
                    slmError = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Clear")
                    }
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.fg2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .overlay(
                        Rectangle()
                            .strokeBorder(palette.line, lineWidth: Layout.hairline)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if let err = slmError {
                Text(err)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.crit)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }
        }
    }

    private func slmButton(title: String, icon: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(palette.fg)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.accentDim, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - SLM action handlers

    private func handleGenerateNarrative() {
        let p = patient
        let id = state.casualtyId
        Task { @MainActor in
            slmError = nil
            isGeneratingNarrative = true
            defer { isGeneratingNarrative = false }

            let availability = TCCCLanguageModel.availability()
            guard availability == .available else {
                slmError = unavailabilityMessage(availability)
                return
            }

            do {
                let text = try await narrativeGenerator.generate(for: p, casualtyId: id)
                state.encounterNarrative = text
            } catch {
                slmError = error.localizedDescription
            }
        }
    }

    private func handleGenerateZMIST() {
        let p = patient
        let id = state.casualtyId
        Task { @MainActor in
            slmError = nil
            isGeneratingZMIST = true
            defer { isGeneratingZMIST = false }

            let availability = TCCCLanguageModel.availability()
            guard availability == .available else {
                slmError = unavailabilityMessage(availability)
                return
            }

            do {
                let text = try await zmistGenerator.generate(for: p, casualtyId: id)
                state.zmistNarrative = text
            } catch {
                slmError = error.localizedDescription
            }
        }
    }

    private func unavailabilityMessage(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Foundation Model not supported on this device."
            case .appleIntelligenceNotEnabled:
                return "Enable Apple Intelligence in Settings."
            case .modelNotReady:
                return "Foundation Model is still downloading."
            @unknown default:
                return "Foundation Model unavailable."
            }
        @unknown default:
            return "Foundation Model unavailable."
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
                detail: "\(HandoffQR.payloadKilobytes(for: patient)) KB · Tap to share",
                isReady: patient != nil,
                action: { shareJSON() }
            )
            ExportCard(
                icon: "waveform",
                title: "Audio + Transcript",
                detail: audioStatusDetail,
                isReady: hasAudioOrTranscript,
                action: { shareAudioAndTranscript() }
            )
            ExportCard(
                icon: "tablecells",
                title: "Vitals CSV",
                detail: vitalsCsvDetail,
                isReady: vitalsFieldCount > 0,
                action: { shareVitalsCSV() }
            )
        }
    }

    // MARK: - Share actions

    private var hasAudioOrTranscript: Bool {
        !state.transcript.isEmpty || state.lastRecordingURL != nil
    }

    private func shareJSON() {
        guard let url = HandoffExports.writeJSON(for: patient, casualtyId: state.casualtyId) else { return }
        shareItems = [url]
        shareSheetVisible = true
    }

    private func shareAudioAndTranscript() {
        var items: [Any] = []
        if let audio = state.lastRecordingURL,
           FileManager.default.fileExists(atPath: audio.path) {
            items.append(audio)
        }
        if !state.transcript.isEmpty,
           let txt = HandoffExports.writeTranscript(transcript: state.transcript, casualtyId: state.casualtyId) {
            items.append(txt)
        }
        guard !items.isEmpty else { return }
        shareItems = items
        shareSheetVisible = true
    }

    private func shareVitalsCSV() {
        guard let url = HandoffExports.writeVitalsCSV(history: state.vitalsHistory, casualtyId: state.casualtyId) else { return }
        shareItems = [url]
        shareSheetVisible = true
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
        var parts: [String] = []
        let kb = HandoffExports.sizeKB(of: state.lastRecordingURL)
        if kb > 0 { parts.append("\(kb) KB audio") }
        let lines = state.transcript.count
        if lines > 0 { parts.append("\(lines) lines") }
        if parts.isEmpty { return "Tap RECORD to capture" }
        return parts.joined(separator: " · ") + " · Tap to share"
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
/// Includes Save-to-Photos and Share buttons so the medic can hand the code
/// off via any local mechanism (AirDrop, Photos library, Files).
private struct QRSheet: View {
    let payload: Data

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var qrCG: CGImage?
    @State private var showShare: Bool = false
    @State private var saveStatus: String?

    var body: some View {
        ZStack {
            palette.bg
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header

                GeometryReader { geo in
                    let side = min(min(geo.size.width, geo.size.height), 380)
                    ZStack {
                        Rectangle()
                            .fill(palette.fg)
                        if let cg = qrCG {
                            Image(decorative: cg, scale: 1, orientation: .up)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                        } else {
                            Text("QR unavailable")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.bg)
                        }
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                actionRow

                Text(footerText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg2)
                    .padding(.bottom, 14)
            }
            .padding(.top, 14)
        }
        .task {
            qrCG = HandoffQR.generateImage(from: payload, scale: 12)
        }
        .sheet(isPresented: $showShare) {
            if let img = qrUIImage() {
                ShareSheet(items: [img], onDismiss: { showShare = false })
            }
        }
    }

    private var header: some View {
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
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                saveToPhotos()
            } label: {
                actionButtonLabel(icon: "square.and.arrow.down", title: "Save to Photos")
            }
            .buttonStyle(.plain)
            .disabled(qrCG == nil)

            Button {
                showShare = true
            } label: {
                actionButtonLabel(icon: "square.and.arrow.up", title: "Share")
            }
            .buttonStyle(.plain)
            .disabled(qrCG == nil)
        }
        .padding(.horizontal, 14)
    }

    private func actionButtonLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(palette.fg)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    private var footerText: String {
        if let status = saveStatus { return status }
        return "\(payload.count) bytes · on-device only"
    }

    private func qrUIImage() -> UIImage? {
        guard let cg = qrCG else { return nil }
        return UIImage(cgImage: cg)
    }

    private func saveToPhotos() {
        guard let img = qrUIImage() else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        saveStatus = "Saved to Photos · scan from another device"
    }
}
