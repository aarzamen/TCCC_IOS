import SwiftUI

struct LiveCaptureScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    @State private var recognizer: SpeechRecognizer?
    @State private var streamingTask: Task<Void, Never>?
    @State private var elapsedDisplay: String = "00:00:00"
    @State private var elapsedTickerTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .liveCapture,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: trailingKickerLabel,
                trailingKickerValue: trailingKickerValue
            )

            HStack(spacing: Layout.gridGap) {
                transcriptPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                capturePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                extractedPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(leadingLabel: "HANDOFF", trailingLabel: "VITALS")
        }
        .background(palette.bg)
        .task {
            recognizer = SpeechRecognizer(levels: state.audioLevels)
        }
        .onDisappear {
            streamingTask?.cancel()
            elapsedTickerTask?.cancel()
            Task { await recognizer?.stop() }
        }
    }

    // MARK: - Panels

    private var transcriptPanel: some View {
        Panel("Transcript", titleIcon: "mic", action: liveActionLabel, padded: false) {
            transcriptList
        }
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.transcript) { line in
                        TranscriptLineView(line: line)
                            .id(line.id)
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: Layout.hairline)
                    }

                    if !state.partialTranscript.isEmpty {
                        TranscriptLineView(
                            line: TranscriptLine(
                                speaker: .medic,
                                text: state.partialTranscript,
                                isPartial: true
                            )
                        )
                        .id("partial")
                    }

                    if state.transcript.isEmpty && state.partialTranscript.isEmpty {
                        emptyTranscriptHint
                    }
                }
            }
            .onChange(of: state.transcript.count) {
                if let last = state.transcript.last {
                    withAnimation(.standard) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: state.partialTranscript) {
                if !state.partialTranscript.isEmpty {
                    withAnimation(.fast) {
                        proxy.scrollTo("partial", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyTranscriptHint: some View {
        VStack(spacing: 8) {
            Text("Awaiting voice intake")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            Text("Tap RECORD to start on-device transcription")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.vertical, 24)
    }

    private var capturePanel: some View {
        Panel("Capture", titleIcon: "record.circle", padded: true) {
            VStack(alignment: .leading, spacing: 12) {
                RecCapsule(isRecording: state.isRecording, elapsed: elapsedDisplay)

                AudioMeterView(levels: state.audioLevels, isActive: state.isRecording)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                voiceCommandsBlock

                Spacer(minLength: 4)

                bigButtonsRow

                if let error = state.recognitionError {
                    Text(error)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.crit)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var voiceCommandsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                VoiceCommandChip(label: "MARK", systemImage: "bookmark") {
                    state.appendSystem("MARK · \(currentTimestamp())")
                }
                VoiceCommandChip(label: "MED GIVEN", systemImage: "syringe") {
                    state.appendSystem("MED GIVEN · pending dose")
                }
                VoiceCommandChip(label: "VITALS", systemImage: "heart") {
                    state.appendSystem("VITALS · pending input")
                }
                VoiceCommandChip(label: "NEXT", systemImage: "arrow.right") {
                    state.nextScreen()
                }
            }
        }
    }

    private var bigButtonsRow: some View {
        HStack(spacing: 6) {
            BigButton(
                state.isRecording ? "Pause" : "Record",
                systemImage: state.isRecording ? "pause.fill" : "mic.fill",
                style: .standard
            ) {
                Task { await toggleRecording() }
            }

            BigButton("Mark", systemImage: "bookmark.fill", style: .accent) {
                state.appendSystem("MARK · \(currentTimestamp())")
            }
        }
    }

    private var extractedPanel: some View {
        Panel("Extracted", action: "\(state.transcript.count)", padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                if state.transcript.isEmpty {
                    PlaceholderBody(label: "Auto-extracted facts")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.transcript.suffix(8)) { line in
                                ExtractedRowPreview(line: line)
                                Rectangle()
                                    .fill(palette.line)
                                    .frame(height: Layout.hairline)
                            }
                        }
                    }

                    Text("Engine port pending — Phase 4")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(palette.fg3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Helpers

    private var liveActionLabel: String {
        if state.recognitionError != nil { return "ERROR" }
        if state.isRecording { return "● LIVE" }
        return "READY"
    }

    private var trailingKickerLabel: String {
        state.isRecording ? "RECORDING" : "STANDBY"
    }

    private var trailingKickerValue: String {
        state.isRecording ? elapsedDisplay : "—"
    }

    private func currentTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func toggleRecording() async {
        if state.isRecording {
            streamingTask?.cancel()
            elapsedTickerTask?.cancel()
            await recognizer?.stop()
            state.isRecording = false
            return
        }

        guard let recognizer else { return }
        state.clearError()

        do {
            try await recognizer.authorize()
        } catch {
            state.recognitionError = error.localizedDescription
            return
        }

        do {
            let stream = try await recognizer.start()
            state.isRecording = true
            state.sessionStart = Date()
            startElapsedTicker()
            streamingTask = Task { @MainActor in
                for await update in stream {
                    if Task.isCancelled { break }
                    if update.isFinal {
                        state.appendFinal(update.text)
                    } else {
                        state.partialTranscript = update.text
                    }
                }
                state.isRecording = false
                state.partialTranscript = ""
            }
        } catch {
            state.recognitionError = error.localizedDescription
            state.isRecording = false
        }
    }

    private func startElapsedTicker() {
        elapsedTickerTask?.cancel()
        let start = state.sessionStart
        elapsedTickerTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Int(Date().timeIntervalSince(start))
                let h = elapsed / 3600
                let m = (elapsed % 3600) / 60
                let s = elapsed % 60
                elapsedDisplay = String(format: "%02d:%02d:%02d", h, m, s)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

private struct ExtractedRowPreview: View {
    let line: TranscriptLine
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 12))
                .foregroundStyle(palette.fg2)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(line.speaker == .system ? "EVENT" : "CAPTURED")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg2)
                Text(line.text)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.fg)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(line.displayTimestamp)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
