import SwiftUI
import TCCCAudio
import os

/// Live mic capture against Granite Speech, surfaced in DevTools per
/// Sprint 1 v3 §G3.
///
/// **Implementation**: record-then-transcribe. The mic-capture pattern
/// reuses the `AVAudioEngine` + `AVAudioFile` AAC writer plumbing in
/// `GraniteSpeechTranscriptStream` (which mirrors `SpeechRecognizer`).
/// The transcript appears once after `STOP` is tapped — real-time
/// chunked decode is parked for Sprint 2/3 polish (see
/// `Packages/TCCCAudio/CLAUDE.md` G2 §"Known limitations" §1).
///
/// **Memory gauges** are powered by `MemoryMonitorObserver` (1 Hz poll
/// + DispatchSource memory-pressure subscription). The `phys_footprint`
/// reading is the load-bearing one — that's what jetsam fires on; the
/// other two are for context.
struct GraniteLiveView: View {
    let state: AppState
    let onBack: () -> Void

    @Environment(\.palette) private var palette
    @State private var monitor = MemoryMonitorObserver(pollInterval: 1.0)

    private static let logger = Logger(subsystem: "ai.tccc", category: "granite-live")

    @State private var phase: Phase = .idle
    @State private var transcriptText: String = ""
    @State private var resolverSource: GraniteSpeechModelResolver.Source?
    @State private var lifecycleTask: Task<Void, Never>?
    @State private var streamWatchTask: Task<Void, Never>?
    @State private var stream: GraniteSpeechTranscriptStream?
    @State private var lastError: String?

    /// Wall-clock start of the current recording session. Drives the
    /// long-form warning banner's 60-s duration sentinel. Reset on
    /// stop / failed / complete.
    @State private var recordingStartedAt: Date?

    /// Per-session CSV logger writing to `Documents/MemoryMonitorLog.csv`
    /// (v3 §13 criterion 7). Allocated on recording start, drained on
    /// every monitor tick + pressure transition + lifecycle event.
    @State private var csvLogger: MemoryMonitorCSVLogger?

    /// Sprint 1 long-form-recording duration ceiling. Past this point
    /// the unbounded actor mailbox is observed accumulating buffer
    /// copies faster than the AAC writer drains them (G3 known
    /// limitation §2). The banner fires; the operator can stop or
    /// continue at their own risk.
    private static let longFormWarningSeconds: TimeInterval = 60.0

    private enum Phase: Equatable {
        case idle
        case priming
        case recording
        case transcribing
        case complete
        case failed(message: String)
    }

    private var hasBookmark: Bool {
        state.graniteSpeechBookmarkStore.hasBookmark
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(alignment: .leading, spacing: Layout.gridGap) {
                statusPanel
                memoryPanel
                if shouldShowLongFormBanner {
                    longFormWarningBanner
                }
                transcriptPanel
                controls
            }
            .padding(.horizontal, Layout.outerPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            monitor.start()
        }
        .onDisappear {
            monitor.stop()
            lifecycleTask?.cancel()
            streamWatchTask?.cancel()
            Task { await stream?.stopImmediate() }
            csvLogger = nil
        }
        .onChange(of: monitor.current) { _, reading in
            csvLogger?.append(reading, pressure: monitor.pressure)
        }
        .onChange(of: monitor.pressure) { _, pressure in
            csvLogger?.append(monitor.current, pressure: pressure, event: "pressure_\(pressure.rawValue)")
        }
    }

    // MARK: - Panels

    private var statusPanel: some View {
        Panel("Granite Live", titleIcon: "mic.circle.fill", action: phaseLabel, padded: true) {
            VStack(alignment: .leading, spacing: 8) {
                row(label: "MODEL", value: GraniteSpeechModelResolver.defaultModelID)
                row(label: "BOOKMARK", value: hasBookmark ? "Configured" : "Missing — use Settings")
                if let source = resolverSource {
                    row(label: "RESOLVED FROM", value: source.rawValue)
                }
                if let err = lastError {
                    row(label: "ERROR", value: err)
                }
            }
        }
    }

    private var memoryPanel: some View {
        Panel("Memory", titleIcon: "memorychip", action: pressureLabel, padded: true) {
            HStack(alignment: .top, spacing: 16) {
                memoryColumn(
                    label: "Resident",
                    valueMB: monitor.current.residentMB,
                    isPrimary: false
                )
                memoryColumn(
                    label: "Footprint",
                    valueMB: monitor.current.physFootprintMB,
                    isPrimary: true
                )
                memoryColumn(
                    label: "Available",
                    valueMB: monitor.current.availableMB,
                    isPrimary: false
                )
            }
            if monitor.pressure != .normal {
                pressureBanner
                    .padding(.top, 8)
            }
        }
    }

    private var transcriptPanel: some View {
        Panel("Transcript", titleIcon: "text.alignleft", action: nil, padded: true) {
            ScrollView {
                Text(transcriptText.isEmpty ? "—" : transcriptText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                onBack()
            } label: {
                Text("Back")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.fg2)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .overlay(
                        Rectangle()
                            .strokeBorder(palette.line, lineWidth: Layout.hairline)
                    )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                handleRecordTap()
            } label: {
                Text(recordButtonLabel)
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(recordButtonForeground)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(recordButtonBackground)
                    .overlay(
                        Rectangle()
                            .strokeBorder(recordButtonBorder, lineWidth: Layout.hairline)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)
        }
    }

    // MARK: - Record-button state

    private var recordButtonLabel: String {
        switch phase {
        case .idle:                  hasBookmark ? "Record" : "Configure model first"
        case .priming:               "Priming model…"
        case .recording:             "Stop"
        case .transcribing:          "Transcribing…"
        case .complete:              "Record again"
        case .failed:                "Retry"
        }
    }

    private var recordButtonForeground: Color {
        switch phase {
        case .recording:    return palette.bg
        case .priming, .transcribing:
            return palette.fg3
        default:
            return canRecord ? palette.crit : palette.fg3
        }
    }

    private var recordButtonBackground: Color {
        phase == .recording ? palette.crit : Color.clear
    }

    private var recordButtonBorder: Color {
        switch phase {
        case .recording:                    return palette.crit
        case .priming, .transcribing:       return palette.line
        default:                            return canRecord ? palette.crit : palette.line
        }
    }

    private var canRecord: Bool {
        guard hasBookmark else { return false }
        switch phase {
        case .priming, .transcribing: return false
        default:                       return true
        }
    }

    // MARK: - Lifecycle

    private func handleRecordTap() {
        switch phase {
        case .idle, .complete, .failed:
            startRecording()
        case .recording:
            stopRecording()
        case .priming, .transcribing:
            break
        }
    }

    private func startRecording() {
        guard hasBookmark else { return }
        lifecycleTask?.cancel()
        streamWatchTask?.cancel()
        lastError = nil
        transcriptText = ""
        resolverSource = nil
        recordingStartedAt = nil
        csvLogger = MemoryMonitorCSVLogger()
        csvLogger?.append(monitor.current, pressure: monitor.pressure, event: "record_start")

        let runtime = GraniteSpeechRuntime(
            resolver: GraniteSpeechModelResolver(
                bookmarkStore: state.graniteSpeechBookmarkStore,
                hfCacheLookup: { modelID in
                    HFHubCache.directory(for: modelID).flatMap { dir in
                        HFHubCache.contains(modelId: modelID) ? dir : nil
                    }
                }
            )
        )
        let newStream = GraniteSpeechTranscriptStream(runtime: runtime)
        stream = newStream

        phase = .priming
        lifecycleTask = Task {
            do {
                try await newStream.authorize()
                try await newStream.prime()
                let source = await newStream.primedSource
                let live = try await newStream.start(audioURL: nil)

                await MainActor.run {
                    self.resolverSource = source
                    self.recordingStartedAt = Date()
                    self.csvLogger?.append(self.monitor.current, pressure: self.monitor.pressure, event: "primed")
                    self.phase = .recording
                }

                // Watch the stream for the final RecognitionUpdate (emitted
                // after stop() runs runtime.transcribe over the captured
                // file). The stream finishes after the final update.
                streamWatchTask = Task {
                    for await update in live {
                        await MainActor.run {
                            self.transcriptText = update.text
                            if update.isFinal {
                                self.csvLogger?.append(self.monitor.current, pressure: self.monitor.pressure, event: "transcribe_complete")
                                self.recordingStartedAt = nil
                                self.phase = .complete
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.csvLogger?.append(self.monitor.current, pressure: self.monitor.pressure, event: "failed")
                    self.recordingStartedAt = nil
                    self.phase = .failed(message: error.localizedDescription)
                }
                Self.logger.error("Granite Live start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func stopRecording() {
        guard let s = stream else { return }
        phase = .transcribing
        csvLogger?.append(monitor.current, pressure: monitor.pressure, event: "record_stop")
        lifecycleTask?.cancel()
        lifecycleTask = Task {
            await s.stop()
        }
    }

    // MARK: - Long-form warning banner

    private var recordingDuration: TimeInterval {
        guard let started = recordingStartedAt else { return 0 }
        return Date().timeIntervalSince(started)
    }

    private var shouldShowLongFormBanner: Bool {
        guard phase == .recording else { return false }
        if recordingDuration >= Self.longFormWarningSeconds { return true }
        if monitor.pressure != .normal { return true }
        return false
    }

    private var longFormWarningBanner: some View {
        let isCritical = monitor.pressure == .critical
        let elapsedExceeded = recordingDuration >= Self.longFormWarningSeconds
        let accent = isCritical ? palette.crit : palette.warn
        let icon = isCritical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Long-form recording is unstable in Sprint 1 — see G3 limitations in CLAUDE.md.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(longFormBannerSubtitle(elapsedExceeded: elapsedExceeded, isCritical: isCritical))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(palette.bg2)
        .overlay(
            Rectangle()
                .strokeBorder(accent, lineWidth: Layout.hairline)
        )
    }

    private func longFormBannerSubtitle(elapsedExceeded: Bool, isCritical: Bool) -> String {
        var parts: [String] = []
        if elapsedExceeded {
            parts.append(String(format: "duration %0.0fs ≥ %0.0fs",
                                recordingDuration, Self.longFormWarningSeconds))
        }
        switch monitor.pressure {
        case .normal: break
        case .warning:
            parts.append("memory pressure: warning (≥ 75% of cap)")
        case .critical:
            parts.append("memory pressure: critical (≥ 90% of cap)")
        }
        if parts.isEmpty {
            parts.append("triggered by Sprint 1 G3 known limitations")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private var phaseLabel: String {
        switch phase {
        case .idle:                  "ready"
        case .priming:               "priming"
        case .recording:             "recording"
        case .transcribing:          "transcribing"
        case .complete:              "complete"
        case .failed:                "failed"
        }
    }

    private var pressureLabel: String {
        switch monitor.pressure {
        case .normal:   return "ok"
        case .warning:  return "warn"
        case .critical: return "critical"
        }
    }

    private var pressureBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(monitor.pressure == .critical ? palette.crit : palette.warn)
            Text(monitor.pressure == .critical
                 ? "Memory critical · pause new ASR generation"
                 : "Memory warning · footprint near cap")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.fg)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(palette.bg2)
        .overlay(
            Rectangle()
                .strokeBorder(monitor.pressure == .critical ? palette.crit : palette.warn, lineWidth: Layout.hairline)
        )
    }

    private func memoryColumn(label: String, valueMB: Double, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(palette.fg3)
                .textCase(.uppercase)
            Text(formatMB(valueMB))
                .font(.system(
                    size: isPrimary ? 18 : 14,
                    weight: isPrimary ? .heavy : .semibold,
                    design: .monospaced
                ))
                .foregroundStyle(memoryColor(valueMB: valueMB, isPrimary: isPrimary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memoryColor(valueMB: Double, isPrimary: Bool) -> Color {
        guard isPrimary else { return palette.fg }
        let footprintBytes = UInt64(valueMB * 1_048_576.0)
        if footprintBytes >= monitor.criticalThresholdBytes {
            return palette.crit
        } else if footprintBytes >= monitor.warningThresholdBytes {
            return palette.warn
        }
        return palette.fg
    }

    private func formatMB(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(palette.fg3)
                .textCase(.uppercase)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
