import SwiftUI
import UniformTypeIdentifiers
import Observation
@preconcurrency import AVFAudio

struct YapLabView: View {
    let state: AppState
    let onBack: () -> Void
    @State private var model = YapLabModel()
    @State private var importing = false
    @State private var confirmUnsavedExit = false
    @State private var assetsOpen = false
    @State private var choosingFileBackend = false
    @State private var pendingFileImport = true
    @State private var search = ""
    @State private var playback = YapSourcePlayback()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(state: AppState, onBack: @escaping () -> Void) {
        self.state = state; self.onBack = onBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    playback.stop()
                    Task {
                        await model.cancel()
                        if model.saveError == nil { onBack() }
                        else { confirmUnsavedExit = true }
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left").frame(minHeight: 44)
                }
                Text("YAP LAB").font(.title2.bold())
                Text("LOCAL TRANSCRIPTION · INDEPENDENT SESSIONS").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("New") { playback.stop(); model.newSession() }.disabled(model.busy).frame(minHeight: 44)
                Button("Save") { model.save() }.frame(minHeight: 44)
                ShareLink(item: model.shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                    .frame(minHeight: 44).disabled(model.busy)
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Session title", text: $model.session.title).textFieldStyle(.roundedBorder)
                        controls
                        Divider()
                        Text("PROMPT WORKBENCH").font(.caption.bold())
                        Menu("Apply preset") {
                            ForEach(YapPreset.allCases) { preset in
                                Button(preset.rawValue) { model.apply(preset) }
                            }
                        }.frame(minHeight: 44).disabled(model.busy)
                        Text("System instructions").font(.caption)
                        TextEditor(text: $model.session.systemPrompt).frame(minHeight: 90)
                            .padding(4).background(.quaternary).disabled(model.busy)
                        Text("Task instructions").font(.caption)
                        TextEditor(text: $model.session.taskPrompt).frame(minHeight: 90)
                            .padding(4).background(.quaternary).disabled(model.busy)
                        Button("Generate separate draft") { playback.stop(); model.generate() }
                            .buttonStyle(.borderedProminent).frame(minHeight: 56)
                            .disabled(model.busy || model.transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                        Text("Re-run the same source with another model or prompt. Each draft keeps its source and exact prompts. No clinical extraction runs here.")
                            .font(.caption).foregroundStyle(.secondary)
                        savedSessions
                    }
                }.frame(minWidth: 250, idealWidth: 290, maxWidth: 340)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("RAW RECOGNITION").font(.headline)
                        searchBar
                        Text("Source evidence stays unchanged when generating a draft.").font(.caption).foregroundStyle(.secondary)
                        if model.session.transcripts.isEmpty {
                            Text("Record or import local audio to begin.").foregroundStyle(.secondary).padding(.vertical, 20)
                        }
                        ForEach(model.session.transcripts) { raw in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { playback.stop(); model.selectedTranscriptID = raw.id } label: {
                                    HStack {
                                        Image(systemName: model.transcript?.id == raw.id ? "checkmark.circle.fill" : "circle")
                                        Text(raw.backend.rawValue)
                                        Spacer()
                                        Text(raw.createdAt, style: .time)
                                    }.frame(minHeight: 44)
                                }.disabled(model.busy)
                                Text("\(raw.status) · \(YapTextMetrics.wordCount(raw.text)) words").font(.caption).foregroundStyle(.secondary)
                                if let reason = raw.failureReason {
                                    Text(reason).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                                }
                                Text(raw.text.isEmpty ? AttributedString("No text returned yet.") : highlighted(raw.text)).textSelection(.enabled)
                                ForEach(model.session.results.filter { $0.transcriptID == raw.id }) { result in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("DRAFT · \(result.backend.rawValue) · \(YapTextMetrics.wordCount(result.text)) words").font(.subheadline.bold())
                                        if let elapsed = result.elapsedSeconds {
                                            Text(String(format: "%.1f seconds · includes model loading", elapsed)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(highlighted(result.text)).textSelection(.enabled)
                                        DisclosureGroup("Exact prompts") {
                                            Text(result.systemPrompt + "\n\n" + result.taskPrompt).font(.caption).textSelection(.enabled)
                                        }
                                    }.padding(12).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption)
                Spacer()
                if let savedAt = model.lastSavedAt {
                    Text("Last saved \(savedAt.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                }
                if model.busy { Button("Cancel") { Task { await model.cancel() } }.frame(minHeight: 44) }
            }
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if let error = model.saveError { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .task { model.refresh(); await model.checkReadiness() }
        .sheet(isPresented: $assetsOpen) { OfflineModelPreparationView() }
        .alert("Session could not be saved", isPresented: $confirmUnsavedExit) {
            Button("Keep editing", role: .cancel) { }
            Button("Leave without saving", role: .destructive) { onBack() }
        } message: {
            Text("Your latest changes are still only in memory. Keep editing to retry Save or share the text before leaving.")
        }
        .confirmationDialog("Choose a recognizer for this audio file", isPresented: $choosingFileBackend, titleVisibility: .visible) {
            ForEach(YapASR.allCases.filter(\.supportsFile)) { backend in
                Button("Use \(backend.rawValue)") {
                    model.session.asr = backend
                    performFileAction()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Parakeet currently supports live recording here. Choose Apple Speech or Granite for file transcription.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): playback.stop(); model.importAudio(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // System permission dialogs make the app inactive. Cancelling then
            // aborts the very operation whose permission the operator grants.
            if phase == .background { playback.stop(); Task { await model.cancel() } }
            if phase == .active { Task { await model.checkReadiness() } }
        }
        .onChange(of: model.session.asr) { _, _ in model.refreshPermissions() }
        .onChange(of: model.session.llm) { _, _ in Task { await model.checkReadiness() } }
        .onChange(of: model.busy) { _, busy in if busy { playback.stop() } }
        .onChange(of: model.session.id) { _, _ in playback.stop() }
        .onChange(of: model.selectedTranscriptID) { _, _ in playback.stop() }
        .onDisappear { playback.stop(); Task { await model.cancel() } }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Speech", selection: $model.session.asr) {
                ForEach(YapASR.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(model.busy).frame(minHeight: 44)
            Picker("Language", selection: $model.session.llm) {
                ForEach(YapLLM.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(model.busy).frame(minHeight: 44)
            HStack {
                if model.recording {
                    Button("Stop") { Task { await model.stop() } }.tint(.red)
                        .buttonStyle(.borderedProminent).frame(minHeight: 56)
                } else {
                    Button("Record") { playback.stop(); model.record(clinicalRecording: state.isRecording) }
                        .buttonStyle(.borderedProminent).frame(minHeight: 56).disabled(model.busy || state.isRecording)
                }
                Button("Import audio") { beginFileAction(isImport: true) }.frame(minHeight: 56).disabled(model.busy)
            }
            Button("Re-transcribe saved audio") { beginFileAction(isImport: false) }
                .frame(minHeight: 44).disabled(model.busy || model.sourceAudioFilename == nil)
            if let guidance = model.permissionGuidance {
                Text(guidance).font(.caption).foregroundStyle(.orange)
                if model.canOpenPermissionSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }.frame(minHeight: 44).disabled(model.busy)
                }
            }
            Button("Offline model assets") { assetsOpen = true }.frame(minHeight: 44).disabled(model.busy)
            playbackControls
            if !model.session.asr.supportsFile {
                Text("Parakeet: live capture only. Import and re-transcribe let you choose a recognizer for files.").font(.caption)
            }
            Button("Check models") { Task { await model.checkReadiness() } }.frame(minHeight: 44)
            Text(model.readiness).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func beginFileAction(isImport: Bool) {
        playback.stop()
        pendingFileImport = isImport
        if model.session.asr.supportsFile { performFileAction() }
        else { choosingFileBackend = true }
    }

    private func performFileAction() {
        if pendingFileImport { importing = true }
        else { model.transcribeFile() }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Search raw text and drafts", text: $search)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("yap-search")
                if !search.isEmpty { Button("Clear") { search = "" }.frame(minHeight: 44) }
            }
            if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let rawCount = model.session.transcripts.reduce(0) { $0 + YapTextMetrics.matches(in: $1.text, query: search).count }
                let draftCount = model.session.results.reduce(0) { $0 + YapTextMetrics.matches(in: $1.text, query: search).count }
                Text("Matches · raw: \(rawCount) · drafts: \(draftCount)")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("yap-search-count")
            }
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var rendered = AttributedString()
        var cursor = text.startIndex
        for range in YapTextMetrics.matches(in: text, query: search) {
            rendered.append(AttributedString(String(text[cursor..<range.lowerBound])))
            var match = AttributedString(String(text[range]))
            match.backgroundColor = Color.yellow.opacity(0.4)
            rendered.append(match)
            cursor = range.upperBound
        }
        rendered.append(AttributedString(String(text[cursor...])))
        return rendered
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if playback.isPlaying { playback.stop() }
                else if let filename = model.sourceAudioFilename {
                    do { try playback.play(YapLabStore().audioURL(filename)) }
                    catch { playback.error = "Audio playback failed: \(error.localizedDescription)" }
                }
            } label: {
                Label(playback.isPlaying ? "Stop source audio" : "Play selected source audio",
                    systemImage: playback.isPlaying ? "stop.fill" : "play.fill")
                    .frame(minHeight: 44)
            }
            .disabled(model.busy || (model.sourceAudioFilename) == nil)
            if model.transcript != nil && model.sourceAudioFilename == nil {
                Text("No source audio is linked to this transcript. Import the original recording to compare recognizers.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = playback.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
    private var savedSessions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("SAVED LOCALLY").font(.caption.bold())
            if model.unreadableSessionCount > 0 {
                Text("\(model.unreadableSessionCount) saved session(s) could not be read. Their files are kept; other sessions remain available.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(model.saved) { session in
                Button { playback.stop(); model.reopen(session.id) } label: {
                    VStack(alignment: .leading) {
                        Text(session.title)
                        Text(session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.disabled(model.busy)
            }
        }
    }
}

/// Playback has no input tap, recorder, or permission request. Session ownership
/// is paired so an idle view cannot deactivate another component's audio.
@MainActor @Observable
private final class YapSourcePlayback {
    private(set) var isPlaying = false
    var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var ownsSession = false

    func play(_ url: URL) throws {
        stop()
        error = nil
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default)
            try audio.setActive(true)
            ownsSession = true
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            guard player.prepareToPlay(), player.play() else {
                throw CocoaError(.fileReadCorruptFile)
            }
            isPlaying = true
            completionTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(200)) }
                    catch { return }
                    guard let self else { return }
                    if self.player?.isPlaying != true { self.stop(); return }
                }
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        completionTask?.cancel(); completionTask = nil
        player?.stop(); player = nil; isPlaying = false
        if ownsSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsSession = false
        }
    }
}
