import SwiftUI

struct LiveCaptureScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    /// Recognizer slot is the protocol type so the backend can be
    /// chosen at runtime per `AppState.asrBackend`. Per night-pass B5.
    /// SpeechRecognizer remains the runtime default; Parakeet is
    /// reachable but requires the operator to provide a model
    /// directory in Settings before `start()` will succeed.
    @State private var recognizer: (any TranscriptStream)?
    @State private var streamingTask: Task<Void, Never>?
    @State private var partialCommitTask: Task<Void, Never>?
    @State private var elapsedDisplay: String = "00:00:00"
    @State private var elapsedTickerTask: Task<Void, Never>?

    @State private var isCleaningTranscript: Bool = false
    @State private var cleanError: String?

    /// Auto-scroll-to-latest gating. Flips off when the operator drags the
    /// transcript content downward (scrolling up through history); the
    /// floating "LATEST" chip re-engages it. Per long-form recording plan
    /// L4.1: short sessions are fine being yanked back to bottom on every
    /// new line, but at 90 min the operator wants to read older content
    /// without fighting the scroll.
    @State private var transcriptAutoPinned: Bool = true

    /// Seconds of partial-result stability before we commit it as a final
    /// transcript line and run the extraction engine. SFSpeechRecognizer
    /// won't always fire its own isFinal during continuous narration, so we
    /// don't rely on it.
    ///
    /// Bumped 1.5 -> 2.5s 2026-05-05 after device test: medic narration
    /// has natural mid-sentence pauses shorter than 2s; the previous 1.5s
    /// was committing lines mid-thought. 2.5s matches a comfortable
    /// breath-pause boundary. Tunable later.
    private let silenceDebounce: Double = 2.5

    /// Factory: returns the configured ASR backend per `state.asrBackend`.
    /// Both backends receive a `gainProvider` closure that reads the
    /// live Settings slider value on every audio buffer — so changing
    /// the slider takes effect on the next sample, no restart needed.
    private func makeRecognizer() -> any TranscriptStream {
        // Capture the gain box (Sendable, nonisolated). The audio tap
        // callback runs on AVAudioEngine's render thread; we MUST NOT
        // touch MainActor-isolated AppState properties from there.
        // The box is updated by AppState.audioGainDb's didSet on the
        // MainActor side; the audio thread reads `linear` directly.
        let appState = state
        let gainBox = state.audioGainBox
        let gainProvider: @Sendable () -> Float = {
            gainBox.linear
        }
        switch state.asrBackend {
        case .appleSpeech:
            return SpeechRecognizer(
                levels: state.audioLevels,
                gainProvider: gainProvider
            )
        case .parakeet:
            let p = ParakeetTranscriptStream(
                levels: state.audioLevels,
                gainProvider: gainProvider
            )
            if let dir = state.parakeetModelDirectory {
                Task { await p.setModelDirectory(dir) }
            }
            // Wire download progress back to AppState so the Settings
            // UI can show "Downloading 42%…" while FluidAudio fetches.
            Task {
                await p.setDownloadProgressHandler { fraction in
                    Task { @MainActor in
                        appState.parakeetStatus = .downloading(fraction: fraction)
                    }
                }
            }
            return p
        case .graniteSpeech:
            return GraniteSpeechTranscriptStream()
        }
    }

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
                recognizer = makeRecognizer()
            }
            // Prime the engine so the 30s pre-roll buffer is filling before
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
            // Continuous recording: if a streaming task is in flight (operator
            // tapped RECORD and didn't tap STOP), keep the audio engine, the
            // recognizer, and the partial-commit pipeline alive while they
            // work on other screens. The StatusStrip surfaces a REC badge so
            // they know it's still running. Stop only on explicit STOP tap.
            //
            // When NOT recording (just primed for pre-roll), tear down on
            // disappear to release the mic + battery.
            let isRecording = streamingTask != nil
            if !isRecording {
                streamingTask?.cancel()
                partialCommitTask?.cancel()
                elapsedTickerTask?.cancel()
                Task {
                    await recognizer?.stopImmediate()
                    await recognizer?.unprime()
                }
            }
        }
        // L1.3 — AVAudioSession interruption handlers. AppState's
        // AudioSessionCoordinator flips these flags from a notification
        // observer; the screen reacts here. We treat the flags as one-shot
        // events — clear them as soon as we observe a true edge.
        .onChange(of: state.pendingInterruptionPause) { _, newValue in
            guard newValue else { return }
            state.pendingInterruptionPause = false
            Task { await recognizer?.stopImmediate() }
        }
        .onChange(of: state.pendingInterruptionResume) { _, newValue in
            guard newValue else { return }
            state.pendingInterruptionResume = false
            // If the operator hadn't tapped STOP before the interruption,
            // re-prime the recognizer and restart the streaming task.
            if state.isRecording {
                Task {
                    try? await recognizer?.prime()
                    await beginRecordingAfterInterruption()
                }
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
            // Manual-scroll detection: an upward swipe (dragging content
            // downward through the viewport) disengages auto-pin so the
            // operator can read older lines without being yanked back to
            // the bottom on the next commit. The "LATEST" chip below
            // re-engages it. Per plan L4.1: chosen over GeometryReader
            // offset tracking because SwiftUI's ScrollView doesn't expose
            // the visible-rect bottom without UIScrollView introspection.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if value.translation.height > 20 {
                            transcriptAutoPinned = false
                        }
                    }
            )
            .onChange(of: displayedTranscript.count) {
                guard transcriptAutoPinned else { return }
                if let last = displayedTranscript.last {
                    withAnimation(.standard) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: state.partialTranscript) {
                guard transcriptAutoPinned else { return }
                if !state.partialTranscript.isEmpty {
                    withAnimation(.fast) {
                        proxy.scrollTo("partial", anchor: .bottom)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !transcriptAutoPinned && !displayedTranscript.isEmpty {
                    Button {
                        transcriptAutoPinned = true
                        if let last = displayedTranscript.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        Haptics.tap(.light)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .heavy))
                            Text("LATEST")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.bg2)
                        .overlay(
                            Rectangle()
                                .strokeBorder(palette.accent, lineWidth: Layout.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
        }
    }

    @ViewBuilder
    private var cleanerActionRow: some View {
        if !state.transcript.isEmpty {
            HStack(spacing: 6) {
                if state.transcriptCleaned == nil {
                    Button {
                        Haptics.tap()
                        handleCleanTranscript()
                    } label: {
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
                        Haptics.tap()
                        state.transcriptCleaned = nil
                    } label: {
                        cleanerButtonLabel(icon: "arrow.uturn.backward", title: "Show raw", tinted: false)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Haptics.tap()
                        handleCleanTranscript()
                    } label: {
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
        // Cancel any pending auto-clean — the manual button takes
        // precedence so we don't fight ourselves on the same transcript.
        state.autoCleanTask?.cancel()
        state.autoCleanTask = nil
        let lines = state.transcript
        Task { @MainActor in
            cleanError = nil
            isCleaningTranscript = true
            defer { isCleaningTranscript = false }

            let backend = state.currentBackend
            let availability = await backend.availability
            guard availability == .available else {
                cleanError = availability.message(for: backend.displayName)
                return
            }

            do {
                let cleaner = TranscriptCleaner(backend: backend)
                let cleaned = try await cleaner.clean(lines)
                state.transcriptCleaned = cleaned
            } catch {
                cleanError = error.localizedDescription
            }
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
            partialCommitTask?.cancel()
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
            partialCommitTask?.cancel()
            streamingTask = Task { @MainActor in
                for await update in stream {
                    if Task.isCancelled { break }
                    if update.isFinal {
                        partialCommitTask?.cancel()
                        state.appendFinal(update.text, timestamp: update.timestamp)
                    } else {
                        state.partialTranscript = update.text
                        scheduleSilenceCommit()
                    }
                }
                partialCommitTask?.cancel()
                state.isRecording = false
                state.partialTranscript = ""
            }
        } catch {
            state.recognitionError = error.localizedDescription
            state.isRecording = false
        }
    }

    /// Restart the streaming pipeline after an iOS interruption clears
    /// with `.shouldResume`. Mirrors the start branch of
    /// `toggleRecording()` but skips the authorization prompt — the
    /// operator already authorized before the interruption — and skips
    /// flipping `state.isRecording` since the coordinator path leaves
    /// it true throughout the pause/resume cycle. Bumping
    /// `state.sessionStart` would lie about elapsed time; we leave it
    /// alone so the elapsed clock stays continuous across the
    /// interruption.
    private func beginRecordingAfterInterruption() async {
        guard let recognizer else { return }
        do {
            let url = state.newAudioCaptureURL()
            let stream = try await recognizer.start(audioURL: url)
            state.lastRecordingURL = url
            startElapsedTicker()
            streamingTask?.cancel()
            partialCommitTask?.cancel()
            streamingTask = Task { @MainActor in
                for await update in stream {
                    if Task.isCancelled { break }
                    if update.isFinal {
                        partialCommitTask?.cancel()
                        state.appendFinal(update.text, timestamp: update.timestamp)
                    } else {
                        state.partialTranscript = update.text
                        scheduleSilenceCommit()
                    }
                }
                partialCommitTask?.cancel()
                state.isRecording = false
                state.partialTranscript = ""
            }
        } catch {
            state.recognitionError = error.localizedDescription
            state.isRecording = false
        }
    }

    /// Restart the silence-debounce timer. If partial text stays stable for
    /// `silenceDebounce` seconds, treat it as a finalised line — append to
    /// the transcript, run the engine, then ask the recogniser to start a
    /// fresh context so the next partials don't redundantly include this
    /// text.
    private func scheduleSilenceCommit() {
        partialCommitTask?.cancel()
        let pendingAtSchedule = state.partialTranscript
        guard !pendingAtSchedule.isEmpty else { return }
        partialCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(silenceDebounce * 1_000_000_000))
            if Task.isCancelled { return }
            // Only commit if the partial hasn't changed since the timer was
            // scheduled — otherwise speech is still flowing.
            guard state.partialTranscript == pendingAtSchedule else { return }
            guard !pendingAtSchedule.isEmpty else { return }
            state.appendFinal(pendingAtSchedule)
            await recognizer?.forceFinalize()
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
