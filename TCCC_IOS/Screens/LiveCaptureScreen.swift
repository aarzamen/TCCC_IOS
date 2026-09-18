import SwiftUI

struct LiveCaptureScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    /// Recognizer slot is the protocol type so the backend can be
    /// chosen at runtime per `AppState.asrBackend`. Per night-pass B5.
    /// SpeechRecognizer remains the runtime default; Parakeet is
    /// reachable but requires the operator to provide a model
    /// directory in Settings before `start()` will succeed.
    @State private var primingTask: Task<Void, Never>?
    private var recognizer: (any TranscriptStream)? { state.captureBackendCoordinator.recognizer }
    @State private var streamingTask: Task<Void, Never>?
    @State private var activeGeneration: UUID?
    @State private var isTailing = false
    @State private var isChangingEncounter = false
    @State private var isStartingCapture = false
    @State private var resumeAfterInterruption = false
    @State private var partialCommitTask: Task<Void, Never>?
    /// Watchdog that force-commits the in-flight partial during CONTINUOUS speech,
    /// when the silence debounce never fires (no `silenceDebounce` gap) and on-device
    /// Apple Speech never emits its own `isFinal`. Without it an unbroken narration
    /// accretes into one partial that is discarded when the recogniser tears down.
    @State private var periodicCommitTask: Task<Void, Never>?
    /// Wall-clock of the last committed line; drives the max-interval forced commit.
    @State private var lastCommitAt: Date = Date()
    @State private var elapsedDisplay: String = "00:00:00"
    @State private var elapsedTickerTask: Task<Void, Never>?

    /// All installed backends identify finalized requests explicitly. Their
    /// partials stay previews; only successful completion enters extraction.
    private var usesRequestScopedCapture: Bool {
        true
    }

    /// Auto-scroll-to-latest gating. Flips off when the operator drags the
    /// transcript content downward (scrolling up through history); the
    /// floating "LATEST" chip re-engages it. Per long-form recording plan
    /// L4.1: short sessions are fine being yanked back to bottom on every
    /// new line, but at 90 min the operator wants to read older content
    /// without fighting the scroll.
    @State private var transcriptAutoPinned: Bool = true

    /// Unchanged preview text requests a recognition boundary. Apple also waits
    /// for a current acoustic pause; extraction still requires a successful final.
    private let silenceDebounce: Double = 2.5

    /// Ask the backend to rotate periodically. This is a request, not permission
    /// to cut continuous speech: Apple defers until its boundary policy permits it.
    private let maxCommitInterval: Double = 8.0

    /// Each backend owns automatic gain and reports its processed microphone level.
    private func makeRecognizer(_ backend: AppState.ASRBackend) -> any TranscriptStream {
        let appState = state
        switch backend {
        case .appleSpeech:
            return SpeechRecognizer(
                levels: state.audioLevels
            )
        case .parakeet:
            let p = ParakeetTranscriptStream(
                levels: state.audioLevels
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
            return GraniteSpeechTranscriptStream(levels: state.audioLevels)
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
            state.clinicalAudioRelease = {
                primingTask?.cancel()
                await primingTask?.value
                await state.captureBackendCoordinator.shutdown(factory: makeRecognizer)
                await streamingTask?.value
                state.clinicalAudioRelease = nil
            }
            await state.captureBackendCoordinator.select(state.asrBackend, factory: makeRecognizer)
            let primingRecognizer = recognizer
            primingTask = Task {
                do {
                    try await primingRecognizer?.authorize()
                    guard !Task.isCancelled else { return }
                    try await primingRecognizer?.prime()
                } catch { }
            }
            await primingTask?.value
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
                periodicCommitTask?.cancel()
                elapsedTickerTask?.cancel()
                let pendingPrime = primingTask
                pendingPrime?.cancel()
                Task {
                    await pendingPrime?.value
                    await state.captureBackendCoordinator.shutdown(factory: makeRecognizer)
                }
            }
        }
        .onChange(of: state.asrBackend) { _, _ in
            let pendingPrime = primingTask
            if state.activeCaptureBackend == nil { pendingPrime?.cancel() }
            Task {
                if state.activeCaptureBackend == nil { await pendingPrime?.value }
                await state.captureBackendCoordinator.select(state.asrBackend, factory: makeRecognizer)
            }
        }
        // L1.3 — AVAudioSession interruption handlers. AppState's
        // AudioSessionCoordinator flips these flags from a notification
        // observer; the screen reacts here. We treat the flags as one-shot
        // events — clear them as soon as we observe a true edge.
        .onChange(of: state.pendingInterruptionPause) { _, newValue in
            guard newValue else { return }
            state.pendingInterruptionPause = false
            resumeAfterInterruption = state.isRecording
            if !usesRequestScopedCapture {
                let pending = state.partialTranscript
                if !pending.isEmpty { state.commitProvisional(pending) }
                state.promoteProvisional()
            }
            periodicCommitTask?.cancel()
            partialCommitTask?.cancel()
            Task { await recognizer?.stopImmediate() }
        }
        .onChange(of: state.pendingInterruptionResume) { _, newValue in
            guard newValue else { return }
            state.pendingInterruptionResume = false
            // If the operator hadn't tapped STOP before the interruption,
            // re-prime the recognizer and restart the streaming task.
            if resumeAfterInterruption {
                resumeAfterInterruption = false
                Task {
                    await streamingTask?.value
                    await beginRecordingAfterInterruption()
                }
            }
        }
        .onChange(of: state.captureGeneration) { _, generation in
            guard generation != activeGeneration else { return }
            isChangingEncounter = true
            periodicCommitTask?.cancel(); partialCommitTask?.cancel()
            resumeAfterInterruption = false
            Task {
                await state.captureBackendCoordinator.shutdown(factory: makeRecognizer)
                guard state.captureGeneration == generation else { return }
                isTailing = false
                isChangingEncounter = false
            }
        }
    }

    // MARK: - Panels

    private var transcriptPanel: some View {
        Panel("Transcript", titleIcon: "mic", action: liveActionLabel, padded: false) {
            VStack(spacing: 0) {
                transcriptList
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var displayedTranscript: [TranscriptLine] {
        state.transcript
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
                guard transcriptAutoPinned, let last = displayedTranscript.last else { return }
                // Defer the scroll one runloop tick so SwiftUI finishes laying out the
                // freshly-inserted cell before we compute the target. Scrolling
                // synchronously inside onChange races the layout pass — it resolves the
                // target against the PRE-insert content height and lands on the old
                // bottom, stranding the new line below the fold (the "text falls off /
                // blank panel" symptom). main.async runs after the current layout pass.
                DispatchQueue.main.async {
                    withAnimation(.standard) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: state.partialTranscript) {
                guard transcriptAutoPinned, !state.partialTranscript.isEmpty else { return }
                // Same deferral: the partial cell resizes continuously as text accretes,
                // so scroll only after its new height has been laid out — otherwise the
                // growing tail keeps slipping under the viewport bottom.
                DispatchQueue.main.async {
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
                    state.clinicalEntrySheet = .mark
                }
                VoiceCommandChip(label: "MED GIVEN", systemImage: "syringe") {
                    state.clinicalEntrySheet = .medication
                }
                VoiceCommandChip(label: "VITALS", systemImage: "heart") {
                    state.clinicalEntrySheet = .vitals
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
                isTailing ? "Finishing" : (state.isRecording ? "Pause" : "Record"),
                systemImage: state.isRecording ? "pause.fill" : "mic.fill",
                style: .standard
            ) {
                Task { await toggleRecording() }
            }
            .disabled(isTailing || isChangingEncounter || isStartingCapture)

            BigButton("Mark", systemImage: "bookmark.fill", style: .accent) {
                state.clinicalEntrySheet = .mark
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
            if !usesRequestScopedCapture {
                let pending = state.partialTranscript
                if !pending.isEmpty { state.commitProvisional(pending) }
                state.promoteProvisional()
            }
            isTailing = true
            state.isRecording = false
            let backend = state.activeCaptureBackend
            await recognizer?.stop()
            state.appendSystem(backend == .graniteSpeech
                ? "PROCESSING · transcribing recorded audio"
                : "RECORDING TAIL · 30s capture continuing")
            return
        }
        guard !isTailing, !isChangingEncounter, !isStartingCapture else { return }
        await startRecording(resetElapsedTime: true)
    }

    /// Re-prepare the actual leased backend after interruption and preserve the
    /// elapsed session clock rather than reporting a new encounter start.
    private func beginRecordingAfterInterruption() async {
        guard !isChangingEncounter, !isStartingCapture else { return }
        await startRecording(resetElapsedTime: false)
    }

    private func startRecording(resetElapsedTime: Bool) async {
        isStartingCapture = true
        defer { isStartingCapture = false }
        state.clearError()
        let generationBeforeStart = state.captureGeneration
        let coordinator = state.captureBackendCoordinator
        var reservedLease: CaptureBackendCoordinator.Lease?
        do {
            // Finish old warm-up before replacement; reserve the latest choice
            // before the new backend's authorize/prime/start can suspend.
            let lease = try await coordinator.acquireAfterWarmup(primingTask,
                selectedBackend: { state.asrBackend },
                isValid: { state.captureGeneration == generationBeforeStart && !isChangingEncounter },
                factory: makeRecognizer)
            reservedLease = lease
            let startingRecognizer = try await coordinator.prepare(lease,
                restartingAfterInterruption: !resetElapsedTime,
                isValid: { state.captureGeneration == generationBeforeStart && !isChangingEncounter })
            guard coordinator.isCurrent(lease.id), state.captureGeneration == generationBeforeStart,
                  !Task.isCancelled else { throw CancellationError() }
            let url = state.newAudioCaptureURL()
            let stream = try await startingRecognizer.start(audioURL: url)
            guard coordinator.isCurrent(lease.id), state.captureGeneration == generationBeforeStart,
                  !Task.isCancelled else {
                await startingRecognizer.stopImmediate()
                throw CancellationError()
            }
            state.isRecording = true
            if resetElapsedTime { state.sessionStart = Date() }
            await consume(stream, requestedURL: url, lease: lease, recognizer: startingRecognizer)
        } catch is CancellationError {
            if let reservedLease { await coordinator.finish(reservedLease.id, factory: makeRecognizer) }
        } catch {
            if let reservedLease, coordinator.isCurrent(reservedLease.id) {
                state.recognitionError = error.localizedDescription
                state.isRecording = false
                await coordinator.finish(reservedLease.id, factory: makeRecognizer)
            }
        }
    }

    @MainActor
    private func consume(_ stream: AsyncStream<RecognitionUpdate>, requestedURL: URL,
                         lease: CaptureBackendCoordinator.Lease, recognizer: any TranscriptStream) async {
        streamingTask?.cancel()
        partialCommitTask?.cancel()
        let generation = state.beginCapture(backend: lease.backend)
        activeGeneration = generation
        isTailing = false
        let apple = recognizer as? SpeechRecognizer
        let requestScoped = usesRequestScopedCapture
        state.lastRecordingURL = if let apple { await apple.lastRecordingURL } else { requestedURL }
        startElapsedTicker()
        startPeriodicCommit()
        streamingTask = Task { @MainActor in
            for await update in stream {
                guard !Task.isCancelled, generation == state.captureGeneration else { break }
                if requestScoped {
                    // Shared request identity, finalization, failure evidence,
                    // and operator-decision checks; retained legacy method name.
                    await state.receiveAppleCapture(update, generation: generation)
                    if update.termination != nil {
                        partialCommitTask?.cancel()
                        lastCommitAt = Date()
                    } else if !update.text.isEmpty {
                        scheduleSilenceCommit()
                    }
                } else if update.isFinal {
                    partialCommitTask?.cancel()
                    state.applyFinalEcho(update.text, timestamp: update.timestamp)
                    lastCommitAt = Date()
                } else {
                    state.partialTranscript = update.text
                    scheduleSilenceCommit()
                }
            }
            guard activeGeneration == generation else { return }
            partialCommitTask?.cancel(); periodicCommitTask?.cancel(); elapsedTickerTask?.cancel()
            if generation == state.captureGeneration {
                state.isRecording = false
                state.partialTranscript = ""
                if let apple { state.lastRecordingURL = await apple.lastRecordingURL }
            }
            isTailing = false
            streamingTask = nil
            activeGeneration = nil
            await state.captureBackendCoordinator.finish(lease.id, factory: makeRecognizer)
        }
    }

    /// Restart the silence-debounce timer. Stable previews request a recognition
    /// boundary for Apple/Parakeet; extraction waits for successful finalization.
    /// Granite remains record-then-transcribe and finalizes when stopped.
    private func scheduleSilenceCommit() {
        partialCommitTask?.cancel()
        let pendingAtSchedule = state.partialTranscript
        partialCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(silenceDebounce * 1_000_000_000))
            if Task.isCancelled { return }
            guard let textToCommit = PartialCommitGate.committableText(
                scheduled: pendingAtSchedule, latest: state.partialTranscript) else { return }
            if !usesRequestScopedCapture { state.commitProvisional(textToCommit) }
            lastCommitAt = Date()
            await recognizer?.forceFinalize()
        }
    }

    /// Request periodic progress without promoting a preview directly to a fact.
    /// The backend determines when the audio can safely move to a new request.
    private func startPeriodicCommit() {
        periodicCommitTask?.cancel()
        lastCommitAt = Date()
        periodicCommitTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(maxCommitInterval * 1_000_000_000))
                if Task.isCancelled { break }
                let pending = state.partialTranscript
                // Commit only when speech has accumulated uncommitted past the
                // ceiling; a recent silence-debounce / isFinal commit resets the clock.
                guard !pending.isEmpty,
                      Date() >= lastCommitAt.addingTimeInterval(maxCommitInterval) else { continue }
                await commitPartial(pending)
            }
        }
    }

    /// Request a boundary during continuous speech. Request-scoped backends must
    /// drain and emit a successful terminal update before extraction.
    @MainActor
    private func commitPartial(_ text: String) async {
        partialCommitTask?.cancel()
        if !usesRequestScopedCapture { state.commitProvisional(text) }
        lastCommitAt = Date()
        await recognizer?.forceFinalize()
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
