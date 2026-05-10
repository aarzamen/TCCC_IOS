import SwiftUI
import TCCCAudio
import os

/// Bake-off harness for Granite Speech 4.0 1B 5-bit on physical
/// hardware (Sprint 1 v3 §G2).
///
/// Loads the model via `GraniteSpeechRuntime.prime()`, transcribes
/// the bundled `test_5min.wav` fixture, computes keyword recall
/// against the v1 §6 token list, captures `phys_footprint` deltas
/// at each phase, and appends a row to `BAKEOFF_RESULTS.md` in
/// Documents. Used by the operator + agent to validate that the
/// model produces sane transcripts inside §7's runtime memory cap.
///
/// Prerequisites:
/// - Settings → ASR Backend → Granite Speech (alt) → Select Model
///   Folder. The bake-off uses the same `GraniteSpeechBookmarkStore`
///   the runtime uses.
/// - The bundled fixture (`test_5min.wav`, 16 kHz mono Float32) ships
///   in `TCCC_IOS/Resources/`. Despite the name, the synthesized
///   reading runs ~100 s (macOS `say` reads the §6 narrative fast);
///   the file naming follows the v3 spec convention.
struct GraniteBakeoffView: View {
    let state: AppState
    let onBack: () -> Void

    @Environment(\.palette) private var palette

    private static let logger = Logger(subsystem: "ai.tccc", category: "granite-bakeoff")

    /// Tokens the transcript should contain per the v1 spec §6
    /// acceptance baseline. Substring match, case-insensitive.
    private static let expectedTokens: [String] = [
        "8734", "9120", "44.50", "Reaper", "urgent surgical",
        "GSW", "chest", "AVPU P", "pain", "SpO2",
        "88", "93", "TXA", "Hextend", "chest seal",
        "needle decompression", "NKDA", "Dawson", "RD6942", "6942"
    ]

    private enum Phase: Equatable {
        case idle
        case priming
        case transcribing
        case complete
        case failed(message: String)
    }

    @State private var phase: Phase = .idle
    @State private var transcriptText: String = ""
    @State private var bakeoffTask: Task<Void, Never>?

    @State private var primeMemoryDelta: GraniteSpeechRuntime.PrimeMemoryDelta?
    @State private var transcribeStart: Date?
    @State private var transcribeEnd: Date?
    @State private var peakFootprintBytes: UInt64 = 0
    @State private var keywordHits: [String: Bool] = [:]
    @State private var resolverSource: GraniteSpeechModelResolver.Source?

    private var fixtureURL: URL? {
        Bundle.main.url(forResource: "test_5min", withExtension: "wav")
    }

    private var hasBookmark: Bool {
        state.graniteSpeechBookmarkStore.hasBookmark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.gridGap) {
            statusPanel
            metricsPanel
            transcriptPanel
            controls
        }
        .padding(.horizontal, Layout.outerPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear {
            bakeoffTask?.cancel()
            bakeoffTask = nil
        }
    }

    // MARK: - Panels

    private var statusPanel: some View {
        Panel("Granite Bake-off", titleIcon: "gauge.with.dots.needle.bottom.50percent", action: phaseLabel, padded: true) {
            VStack(alignment: .leading, spacing: 8) {
                row(label: "MODEL", value: GraniteSpeechModelResolver.defaultModelID)
                row(label: "BOOKMARK", value: hasBookmark ? "Configured" : "Missing — use Settings")
                row(label: "FIXTURE", value: fixtureURL != nil ? "test_5min.wav (16 kHz mono)" : "Missing")
                if let source = resolverSource {
                    row(label: "RESOLVED FROM", value: source.rawValue)
                }
            }
        }
    }

    private var metricsPanel: some View {
        Panel("Metrics", titleIcon: "chart.bar.doc.horizontal", action: nil, padded: true) {
            VStack(alignment: .leading, spacing: 8) {
                if let delta = primeMemoryDelta {
                    row(label: "PRIME TIME", value: String(format: "%.2f s", delta.loadDurationSeconds))
                    row(label: "PHYS FOOTPRINT Δ", value: String(format: "%.1f MB", delta.physFootprintDeltaMB))
                    row(label: "PHYS FOOTPRINT (post-load)", value: formatBytes(delta.physFootprintAfterBytes))
                    row(label: "AVAILABLE (post-load)", value: formatBytes(delta.availableAfterBytes))
                } else {
                    row(label: "PRIME TIME", value: "—")
                }
                if let start = transcribeStart, let end = transcribeEnd {
                    row(label: "TRANSCRIBE TIME", value: String(format: "%.2f s", end.timeIntervalSince(start)))
                }
                if peakFootprintBytes > 0 {
                    row(label: "PEAK FOOTPRINT", value: formatBytes(peakFootprintBytes))
                }
                if !keywordHits.isEmpty {
                    let hitCount = keywordHits.values.filter { $0 }.count
                    let total = Self.expectedTokens.count
                    let pct = total > 0 ? Double(hitCount) / Double(total) * 100.0 : 0.0
                    row(label: "KEYWORD RECALL", value: String(format: "%d / %d (%.1f%%)", hitCount, total, pct))
                }
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
            .frame(maxHeight: 200)
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
                runBakeoff()
            } label: {
                Text(runButtonLabel)
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(canRun ? palette.accent : palette.fg3)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Rectangle()
                            .strokeBorder(canRun ? palette.accent : palette.line, lineWidth: Layout.hairline)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canRun)
        }
    }

    // MARK: - Bake-off action

    private var runButtonLabel: String {
        switch phase {
        case .idle:                  hasBookmark ? "Run Bake-off" : "Configure model first"
        case .priming:               "Loading model…"
        case .transcribing:          "Transcribing…"
        case .complete:              "Run Again"
        case .failed:                "Retry"
        }
    }

    private var canRun: Bool {
        guard hasBookmark else { return false }
        guard fixtureURL != nil else { return false }
        switch phase {
        case .priming, .transcribing: return false
        default:                       return true
        }
    }

    private func runBakeoff() {
        guard canRun, let url = fixtureURL else { return }
        bakeoffTask?.cancel()

        // Reset.
        phase = .priming
        transcriptText = ""
        primeMemoryDelta = nil
        transcribeStart = nil
        transcribeEnd = nil
        peakFootprintBytes = 0
        keywordHits = [:]
        resolverSource = nil

        bakeoffTask = Task {
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

            do {
                Self.logger.info("Bake-off starting")
                try await runtime.prime()
                let delta = await runtime.primeMemoryDelta
                let source = await runtime.primedSource
                await MainActor.run {
                    self.primeMemoryDelta = delta
                    self.resolverSource = source
                    self.phase = .transcribing
                    self.transcribeStart = Date()
                }

                let stream = try await runtime.transcribe(audioURL: url)
                var accumulator = ""
                for try await event in stream {
                    let footprint = MemoryMonitor.physFootprintBytes()
                    await MainActor.run {
                        if footprint > self.peakFootprintBytes {
                            self.peakFootprintBytes = footprint
                        }
                    }
                    switch event {
                    case .token(let text):
                        accumulator += text
                        let snapshot = accumulator
                        await MainActor.run {
                            self.transcriptText = snapshot
                        }
                    case .info(let info):
                        Self.logger.info("STT info: \(info.summary, privacy: .public)")
                    case .result(let output):
                        // Some upstream STT pipelines emit `.result`
                        // with `output.text == ""` and rely on the
                        // caller to keep the token-stream accumulator.
                        // Don't blank the panel in that case — only
                        // overwrite when result actually carries text.
                        let final = output.text
                        await MainActor.run {
                            if !final.isEmpty {
                                self.transcriptText = final
                            }
                            self.transcribeEnd = Date()
                        }
                    }
                }

                let finalText = accumulator
                await MainActor.run {
                    if self.transcribeEnd == nil {
                        self.transcribeEnd = Date()
                    }
                    self.keywordHits = Self.expectedTokens.reduce(into: [:]) { acc, token in
                        acc[token] = finalText.range(of: token, options: .caseInsensitive) != nil
                    }
                    self.phase = .complete
                }

                await runtime.unload()

                writeBakeoffRow(
                    primeDelta: delta,
                    transcribeSeconds: (self.transcribeEnd ?? Date()).timeIntervalSince(self.transcribeStart ?? Date()),
                    peakFootprintBytes: self.peakFootprintBytes,
                    transcript: finalText,
                    hits: self.keywordHits
                )
            } catch {
                await runtime.unload()
                await MainActor.run {
                    self.phase = .failed(message: error.localizedDescription)
                }
                Self.logger.error("Bake-off failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    private var phaseLabel: String {
        switch phase {
        case .idle:                  "ready"
        case .priming:               "priming"
        case .transcribing:          "transcribing"
        case .complete:              "complete"
        case .failed:                "failed"
        }
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

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private func writeBakeoffRow(
        primeDelta: GraniteSpeechRuntime.PrimeMemoryDelta?,
        transcribeSeconds: TimeInterval,
        peakFootprintBytes: UInt64,
        transcript: String,
        hits: [String: Bool]
    ) {
        let docs: URL
        do {
            docs = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            return
        }
        let url = docs.appendingPathComponent("BAKEOFF_RESULTS.md")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let primeSec = primeDelta?.loadDurationSeconds ?? 0
        let footprintMB = Double(peakFootprintBytes) / 1_048_576.0
        let recallNum = hits.values.filter { $0 }.count
        let recallTotal = Self.expectedTokens.count
        let recallPct = recallTotal > 0 ? Double(recallNum) / Double(recallTotal) * 100.0 : 0
        let missing = Self.expectedTokens.filter { hits[$0] != true }
        let row = """

        ## \(stamp)
        - Model: `\(GraniteSpeechModelResolver.defaultModelID)`
        - Prime: \(String(format: "%.2f s", primeSec)), Δ\(String(format: "%.1f MB", primeDelta?.physFootprintDeltaMB ?? 0)) phys_footprint
        - Transcribe: \(String(format: "%.2f s", transcribeSeconds)), peak \(String(format: "%.1f MB", footprintMB))
        - Keyword recall: \(recallNum)/\(recallTotal) (\(String(format: "%.1f%%", recallPct)))
        - Missing tokens: \(missing.isEmpty ? "—" : missing.joined(separator: ", "))
        - Transcript:
        ```
        \(transcript)
        ```
        """
        let preface = FileManager.default.fileExists(atPath: url.path)
            ? ""
            : "# Granite Bake-off Results\n\nAuto-generated rows from `GraniteBakeoffView` runs.\n"
        let toAppend = preface + row + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(toAppend.utf8))
        } else {
            try? toAppend.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
