import SwiftUI
import FoundationModels

struct LiveCaptureScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    @State private var recognizer: SpeechRecognizer?
    @State private var streamingTask: Task<Void, Never>?
    @State private var elapsedDisplay: String = "00:00:00"
    @State private var elapsedTickerTask: Task<Void, Never>?

    @State private var cleaner = TranscriptCleaner()
    @State private var isCleaningTranscript: Bool = false
    @State private var cleanError: String?

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

            FooterHints(
                state: state,
                leadingLabel: "HANDOFF",
                trailingLabel: "VITALS"
            )
        }
        .background(palette.bg)
        .task {
            if recognizer == nil {
                recognizer = SpeechRecognizer(levels: state.audioLevels)
            }
            // Prime the engine so the 10s pre-roll buffer is filling before
            // the medic taps RECORD. Permission already granted (or not) —
            // priming is silent on either path.
            do {
                try await recognizer?.authorize()
                try await recognizer?.prime()
            } catch {
                // Authorization may be deferred to first RECORD tap; ignore.
            }
        }
        .onDisappear {
            streamingTask?.cancel()
            elapsedTickerTask?.cancel()
            Task {
                await recognizer?.stopImmediate()
                await recognizer?.unprime()
            }
        }
    }

    // MARK: - Panels

    private var transcriptPanel: some View {
        Panel("Transcript", titleIcon: "mic", action: liveActionLabel, padded: false) {
            VStack(spacing: 0) {
                transcriptList
                    .frame(maxHeight: .infinity)
                cleanerActionRow
            }
        }
    }

    private var displayedTranscript: [TranscriptLine] {
        state.transcriptCleaned ?? state.transcript
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedTranscript) { line in
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

                    if displayedTranscript.isEmpty && state.partialTranscript.isEmpty {
                        emptyTranscriptHint
                    }
                }
            }
            .onChange(of: displayedTranscript.count) {
                if let last = displayedTranscript.last {
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

    @ViewBuilder
    private var cleanerActionRow: some View {
        if !state.transcript.isEmpty {
            HStack(spacing: 6) {
                if state.transcriptCleaned == nil {
                    Button(action: handleCleanTranscript) {
                        cleanerButtonLabel(
                            icon: isCleaningTranscript ? nil : "wand.and.stars",
                            title: isCleaningTranscript ? "Cleaning…" : "Clean transcript",
                            tinted: false
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isCleaningTranscript)
                } else {
                    Button {
                        state.transcriptCleaned = nil
                    } label: {
                        cleanerButtonLabel(icon: "arrow.uturn.backward", title: "Show raw", tinted: false)
                    }
                    .buttonStyle(.plain)
                    Button(action: handleCleanTranscript) {
                        cleanerButtonLabel(
                            icon: "wand.and.stars",
                            title: "Re-clean",
                            tinted: true
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isCleaningTranscript)
                }
                if let err = cleanError {
                    Text(err)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.crit)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.line).frame(height: Layout.hairline)
            }
        }
    }

    private func cleanerButtonLabel(icon: String?, title: String, tinted: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .foregroundStyle(tinted ? palette.accent : palette.fg)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .overlay(
            Rectangle()
                .strokeBorder(tinted ? palette.accentDim : palette.line, lineWidth: Layout.hairline)
        )
    }

    private func handleCleanTranscript() {
        let lines = state.transcript
        Task { @MainActor in
            cleanError = nil
            isCleaningTranscript = true
            defer { isCleaningTranscript = false }

            let availability = TCCCLanguageModel.availability()
            guard availability == .available else {
                cleanError = unavailabilityMessage(availability)
                return
            }

            do {
                let cleaned = try await cleaner.clean(lines)
                state.transcriptCleaned = cleaned
            } catch {
                cleanError = error.localizedDescription
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
                return "Foundation Model unavailable on this device."
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

    private var emptyTranscriptHint: some View {
        VStack(spacing: 12) {
            Text("Awaiting voice intake")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            Text("Tap RECORD to start on-device transcription")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)

            HStack(spacing: 8) {
                Button("Load demo · GSW thigh") {
                    Task { await state.loadDemoTranscript(DemoScenarios.scenario1) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Rectangle().strokeBorder(palette.accentDim, lineWidth: 1))

                Button("Load demo · Femur") {
                    Task { await state.loadDemoTranscript(DemoScenarios.scenario4) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Rectangle().strokeBorder(palette.accentDim, lineWidth: 1))
            }
            .padding(.top, 4)
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
        let facts = ExtractedFact.derive(from: state.primaryPatient)
        return Panel("Extracted", action: "\(facts.count)", padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                if facts.isEmpty {
                    extractedEmptyHint
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(facts) { fact in
                                FactRow(fact: fact)
                                Rectangle()
                                    .fill(palette.line)
                                    .frame(height: Layout.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private var extractedEmptyHint: some View {
        VStack(spacing: 6) {
            Text("No findings yet")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            Text("Facts populate as the engine extracts MARCH, vitals, and interventions from the transcript.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.fg3)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.vertical, 24)
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
            // Tail mode: recognizer keeps consuming for 10s before tearing
            // down. Flip the UI flag immediately so the user gets feedback,
            // but DON'T cancel the streaming task — final transcript lines
            // arrive during the tail and we want them appended.
            await recognizer?.stop()
            state.isRecording = false
            elapsedTickerTask?.cancel()
            state.appendSystem("RECORDING TAIL · 10s capture continuing")
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
            let url = state.newAudioCaptureURL()
            let stream = try await recognizer.start(audioURL: url)
            state.isRecording = true
            state.sessionStart = Date()
            state.lastRecordingURL = url
            startElapsedTicker()
            streamingTask?.cancel()
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

