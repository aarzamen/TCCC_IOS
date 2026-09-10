import SwiftUI
import UIKit
import TCCCDomain
import TCCCReports

/// Screen 05 — structured documentation, explicit sharing and plain QR presentation.
struct HandoffScreen: View {
    let state: AppState

    @Environment(\.palette) private var palette
    @State private var exportError: String?
    @State private var failedExport: String?
    @State private var isExportingPDF = false
    @State private var elapsedTick: Date = Date()
    @State private var shareItems: [Any] = []
    @State private var shareSheetVisible: Bool = false

    private let dd1380Export = DD1380PDFExportService()

    private var patient: PatientState? { state.primaryPatient }

    private static let tickInterval: TimeInterval = 1
    private let timer = Timer.publish(every: HandoffScreen.tickInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .handoff,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "HANDOFF",
                trailingKickerValue: "REVIEW / SHARE"
            )

            GeometryReader { geo in
                let totalGap = Layout.gridGap * 2
                let usable = geo.size.width - totalGap
                // Give export names and missing-field details space to wrap.
                let total: CGFloat = 3.80
                let w1 = usable * (1.55 / total)
                let w2 = usable * (0.90 / total)
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
                        slmBlock(label: "ZMIST · Current assessment", body: state.structuredZMIST, mono: true)
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: Layout.hairline)
                        if let narrative = state.encounterNarrative, !narrative.isEmpty {
                            slmBlock(label: "AI narrative · Review", body: narrative)
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: Layout.hairline)
                        }
                        if let zmist = state.zmistNarrative, !zmist.isEmpty {
                            slmBlock(label: "AI ZMIST rewrite · Review", body: zmist, mono: true)
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
        VStack(alignment: .leading, spacing: 6) {
            FMStatusBadge(state: state)
            HStack(spacing: 6) {
                slmButton(
                    title: "AI summary",
                    icon: "wand.and.stars",
                    isLoading: state.isGeneratingHandoffDraft(.narrative),
                    action: { handleGenerateDraft(.narrative) }
                )
                slmButton(
                    title: "AI Rewrite",
                    icon: "doc.text.fill",
                    isLoading: state.isGeneratingHandoffDraft(.zmist),
                    action: { handleGenerateDraft(.zmist) }
                )
                if state.encounterNarrative != nil || state.zmistNarrative != nil ||
                    state.isGeneratingHandoffDraft(.narrative) || state.isGeneratingHandoffDraft(.zmist) {
                    Button {
                        state.clearHandoffDrafts()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.fg2)
                            .frame(minWidth: Layout.minHitTarget, minHeight: Layout.minHitTarget)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear AI drafts")
                    .accessibilityHint("Keeps the current assessment and structured ZMIST")
                }
            }
            if let error = state.handoffDraftError {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.crit)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
            .frame(maxWidth: .infinity, minHeight: Layout.minHitTarget)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.accentDim, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading || patient == nil)
    }

    // MARK: - Optional model drafts

    private func handleGenerateDraft(_ kind: HandoffDraftKind) {
        guard let request = state.beginHandoffDraft(kind) else { return }
        Task { @MainActor in
            await state.generateHandoffDraft(request)
        }
    }

    private var summaryFooter: some View {
        Text("VERIFY RECORDED FACTS BEFORE HANDOFF")
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
                let events = HandoffTimeline.events(
                    for: patient,
                    sessionStart: state.sessionStart,
                    medevacTransmittedAt: state.lastMedevacTransmitTime
                )
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

    // MARK: - Column 3: Documentation sharing

    private var exportColumn: some View {
        Panel("Share documentation", titleIcon: "square.and.arrow.up", padded: false) {
            GeometryReader { viewport in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        exportCardsBlock
                            .padding(.horizontal, 12)
                            .padding(.top, 12)

                        Rectangle()
                            .fill(palette.line)
                            .frame(height: Layout.hairline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)

                        BigButton("Show QR", systemImage: "qrcode", style: .accent) {
                            state.qrOverlayVisible = true
                        }
                        .disabled(patient == nil)
                        .padding(.horizontal, 12)
                        Text("Plain JSON QR · showing or sharing does not confirm receipt.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var exportCardsBlock: some View {
        // 2026 sprint Phase 4 Task 4.4 — DD 1380 is the **primary**
        // deliverable per §19 Documentation of Care. Layout reflects that:
        // a labeled "Primary" group with the DD-1380 PDF card on top, a
        // divider, then a "Supplementary Exports" group for JSON / Audio /
        // Vitals. Completeness remains distinct from export availability.
        VStack(spacing: 6) {
            exportSubhead("Primary · DD 1380")
            ExportCard(
                icon: "doc.richtext",
                title: "DD-1380 PDF",
                detail: dd1380Detail,
                isReady: patient != nil && !isExportingPDF,
                actionLabel: "Export draft",
                action: { shareDD1380PDF() }
            )

            exportFailure(for: "pdf")
            if isExportingPDF { ProgressView("Preparing PDF…") }

            exportSubhead("Supplementary Exports")
            ExportCard(
                icon: "curlybraces",
                title: "JSON Encounter",
                detail: patient == nil ? "No casualty state" : "\(HandoffQR.payloadKilobytes(for: patient)) KB · structured record",
                isReady: patient != nil,
                action: { shareJSON() }
            )
            exportFailure(for: "json")
            ExportCard(
                icon: "waveform",
                title: "Audio + Transcript",
                detail: audioStatusDetail,
                isReady: hasAudioOrTranscript,
                action: { shareAudioAndTranscript() }
            )
            exportFailure(for: "audio")
            ExportCard(
                icon: "tablecells",
                title: "Vitals CSV",
                detail: vitalsCsvDetail,
                isReady: !state.vitalsLog.isEmpty,
                action: { shareVitalsCSV() }
            )
            exportFailure(for: "csv")
            Button("Review & correct") { state.clinicalEntrySheet = .assessment }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: Layout.minHitTarget)
        }
    }

    private func exportSubhead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(palette.fg2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func exportFailure(for key: String) -> some View {
        if failedExport == key, let exportError {
            Text(exportError + " Retry using the export action.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.crit)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export failed. " + exportError)
        }
    }

    private func beginExport() {
        failedExport = nil
        exportError = nil
    }

    private func failExport(_ key: String, _ message: String) {
        failedExport = key
        exportError = message
    }

    // MARK: - Share actions

    private var hasAudioOrTranscript: Bool {
        !state.transcript.isEmpty || (state.lastRecordingURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }

    /// DD-1380 card detail. Deterministic; readiness informs the text but never
    /// blocks generation (a partial DD1380 beats none).
    private var dd1380Detail: String {
        guard let card = state.makeDD1380Card() else { return "No casualty state" }
        let readiness = DD1380Readiness.evaluate(card: card)
        if readiness.criticalMissing.isEmpty {
            return "Draft · required fields present · review before sharing"
        }
        return "Draft · \(readiness.criticalMissing.count) missing required fields"
    }

    /// Render the deterministic DD-1380 to a protected PDF and hand it to the
    /// iOS share sheet. The only way the file leaves the device is this explicit
    /// operator action. Never crashes on blank fields; never uses LLM output.
    private func shareDD1380PDF() {
        guard !isExportingPDF else { return }
        beginExport()
        guard let card = state.makeDD1380Card() else {
            failExport("pdf", "No casualty state to export.")
            return
        }
        let casualtyId = state.casualtyId
        let documentsURL = state.documentsURL
        let sessionStart = state.sessionStart
        isExportingPDF = true
        Task { @MainActor in
            defer { isExportingPDF = false }
            do {
                let url = try await dd1380Export.export(
                    card: card, casualtyId: casualtyId, documentsURL: documentsURL)
                guard state.casualtyId == casualtyId, state.sessionStart == sessionStart else { return }
                shareItems = [url]
                shareSheetVisible = true
                state.appendSystem("DD-1380 PDF · generated on-device")
            } catch {
                failExport("pdf", error.localizedDescription)
            }
        }
    }

    private func shareJSON() {
        beginExport()
        guard let url = HandoffExports.writeJSON(for: patient, casualtyId: state.casualtyId) else {
            failExport("json", "Could not write the JSON file.")
            return
        }
        shareItems = [url]
        shareSheetVisible = true
    }

    private func shareAudioAndTranscript() {
        beginExport()
        do {
            shareItems = try HandoffAudioExport.items(audioURL: state.lastRecordingURL,
                transcript: state.transcript, casualtyId: state.casualtyId)
            shareSheetVisible = true
        } catch {
            failExport("audio", error.localizedDescription)
        }
    }

    private func shareVitalsCSV() {
        beginExport()
        do {
            let url = try HandoffExports.writeVitalsCSV(readings: state.vitalsLog, casualtyId: state.casualtyId)
            shareItems = [url]
            shareSheetVisible = true
        } catch {
            failExport("csv", error.localizedDescription)
        }
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

    private var vitalsCsvDetail: String {
        let count = state.vitalsLog.count
        guard count > 0 else { return "No recorded readings" }
        return "\(count) retained readings · recorded times + AVPU"
    }

}

/// Only explicitly supplied current-encounter artifacts enter clinical sharing.
/// Diagnostics have their own export workflow and are never discovered here.
@MainActor
enum HandoffAudioExport {
    enum ExportError: LocalizedError {
        case transcriptWriteFailed, noArtifacts
        var errorDescription: String? {
            switch self {
            case .transcriptWriteFailed: "Could not write the transcript file."
            case .noArtifacts: "No saved audio or transcript is available."
            }
        }
    }

    static func items(audioURL: URL?, transcript: [TranscriptLine], casualtyId: String) throws -> [URL] {
        var items: [URL] = []
        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) { items.append(audioURL) }
        if !transcript.isEmpty {
            guard let textURL = HandoffExports.writeTranscript(transcript: transcript, casualtyId: casualtyId) else {
                throw ExportError.transcriptWriteFailed
            }
            items.append(textURL)
        }
        guard !items.isEmpty else { throw ExportError.noArtifacts }
        return items
    }
}

// MARK: - QR sheet

/// Modal sheet showing the offline QR code for the selected payload.
/// Sharing uses the system sheet without claiming delivery or receipt.
private struct QRSheet: View {
    let payload: Data

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var qrCG: CGImage?
    @State private var showShare: Bool = false

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

                Text("\(payload.count) bytes · plain JSON · no receipt confirmation")
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
            Image(systemName: "qrcode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text("PATIENT RECORD QR")
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
        .frame(maxWidth: .infinity, minHeight: Layout.minHitTarget)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    private func qrUIImage() -> UIImage? {
        guard let cg = qrCG else { return nil }
        return UIImage(cgImage: cg)
    }

}
