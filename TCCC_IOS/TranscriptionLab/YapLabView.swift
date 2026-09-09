import SwiftUI
import UniformTypeIdentifiers
import Observation
@preconcurrency import AVFAudio

struct YapLabView: View {
    let state: AppState
    let onBack: () -> Void
    @State private var model = YapLabModel()
    @State private var importing = false
    @State private var assetsOpen = false
    @State private var search = ""
    @State private var playback = YapSourcePlayback()
    @Environment(\.scenePhase) private var scenePhase

    init(state: AppState, onBack: @escaping () -> Void) {
        self.state = state; self.onBack = onBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { playback.stop(); Task { await model.cancel(); onBack() } } label: {
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
                            .disabled(model.busy || model.transcript?.text.isEmpty != false)
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
                if model.busy { Button("Cancel") { Task { await model.cancel() } }.frame(minHeight: 44) }
            }
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .task { model.refresh(); await model.checkReadiness() }
        .sheet(isPresented: $assetsOpen) { OfflineModelPreparationView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): playback.stop(); model.importAudio(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.stop(); Task { await model.cancel() } }
        }
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
                Button("Import audio") { playback.stop(); importing = true }.frame(minHeight: 56).disabled(model.busy)
            }
            Button("Re-transcribe saved audio") { playback.stop(); model.transcribeFile() }
                .frame(minHeight: 44).disabled(model.busy || model.session.audioFilename == nil)
            Button("Offline model assets") { assetsOpen = true }.frame(minHeight: 44).disabled(model.busy)
            playbackControls
            if !model.session.asr.supportsFile {
                Text("Parakeet: live capture only in this lab. Imported audio is retained but requires an explicitly selected file-capable backend.").font(.caption)
            }
            Button("Check models") { Task { await model.checkReadiness() } }.frame(minHeight: 44)
            Text(model.readiness).font(.caption).foregroundStyle(.secondary)
        }
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
                else if let filename = model.transcript?.audioFilename ?? model.session.audioFilename {
                    do { try playback.play(YapLabStore().audioURL(filename)) }
                    catch { playback.error = "Audio playback failed: \(error.localizedDescription)" }
                }
            } label: {
                Label(playback.isPlaying ? "Stop source audio" : "Play selected source audio",
                    systemImage: playback.isPlaying ? "stop.fill" : "play.fill")
                    .frame(minHeight: 44)
            }
            .disabled(model.busy || (model.transcript?.audioFilename ?? model.session.audioFilename) == nil)
            if let error = playback.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
    private var savedSessions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("SAVED LOCALLY").font(.caption.bold())
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
