import Foundation
import Observation
import Speech
import TCCCAudio

@MainActor @Observable
final class YapLabModel {
    var session = YapLabSession()
    var saved: [YapLabSession] = []
    var selectedTranscriptID: UUID?
    var busy = false
    var recording = false
    var status = "Ready. Models run on this device; install assets in Model Setup."
    var error: String?
    var readiness = "Check models to inspect availability."
    private let store: YapLabStore
    private var gate = YapRunGate()
    private var operation: Task<Void, Never>?
    private var capture: (any TranscriptStream)?

    init(store: YapLabStore = YapLabStore()) { self.store = store }
    var transcript: YapTranscript? {
        session.transcripts.first { $0.id == selectedTranscriptID }
            ?? session.transcripts.last { $0.audioFilename == session.audioFilename }
    }
    var sourceAudioFilename: String? {
        if let selectedTranscriptID,
           let selected = session.transcripts.first(where: { $0.id == selectedTranscriptID }) {
            return selected.audioFilename ?? session.audioFilename
        }
        return session.audioFilename
    }
    func selectCurrentAudioSource() {
        selectedTranscriptID = session.transcripts.last(where: { $0.audioFilename == session.audioFilename })?.id
    }
    var shareText: String {
        var parts = ["YAP LAB — \(session.title)", "Independent transcription experiment; generated text is unverified."]
        for raw in session.transcripts {
            parts.append("RAW · \(raw.backend.rawValue) · \(raw.status)\n\(raw.text)")
            for result in session.results where result.transcriptID == raw.id {
                parts.append("DRAFT · \(result.backend.rawValue)\nSYSTEM: \(result.systemPrompt)\nTASK: \(result.taskPrompt)\n\(result.text)")
            }
        }
        return parts.joined(separator: "\n\n")
    }
    func refresh() { do { saved = try store.list() } catch { self.error = error.localizedDescription } }
    func save() {
        do { try store.save(session); refresh() }
        catch { self.error = "Session save failed: \(error.localizedDescription)" }
    }
    func newSession() {
        guard !busy else { return }
        error = nil
        save()
        guard error == nil else { return }
        session = YapLabSession(); selectedTranscriptID = nil; status = "New session."
    }
    func reopen(_ id: UUID) {
        guard !busy else { return }
        error = nil
        save()
        guard error == nil else { return }
        do { session = try store.load(id); selectCurrentAudioSource(); status = "Saved session reopened." }
        catch { self.error = error.localizedDescription }
    }
    func apply(_ preset: YapPreset) { session.systemPrompt = preset.system; session.taskPrompt = preset.task }
    func checkReadiness() async {
        let selected = session.llm
        let availability = await selected.makeBackend().availability
        guard selected == session.llm else { return }
        let speech = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let appleReady = speech?.isAvailable == true && speech?.supportsOnDeviceRecognition == true
        let parakeetReady = OfflineModelAssets.parakeetDirectory != nil
        readiness = "Parakeet local files: \(parakeetReady ? "installed" : "missing"). Apple Speech: \(appleReady ? "on-device supported; permission required" : "unavailable"). \(selected.rawValue): \(availability == .available ? "assets available" : availability.message(for: selected.rawValue)) Alternate ASR requires installed assets; Parakeet supports live capture here, Granite transcribes after Stop."
    }
    func record(clinicalRecording: Bool) {
        guard !busy else { return }
        guard !clinicalRecording else { error = "End clinical recording before opening a lab microphone."; return }
        error = nil
        do {
            try store.prepare()
            let name = UUID().uuidString + ".m4a"
            session.audioFilename = name
            let audioURL = try store.audioURL(name)
            let selected = session.asr
            let stream: any TranscriptStream
            switch selected {
            case .apple: stream = SpeechRecognizer(levels: nil)
            case .parakeet: stream = ParakeetTranscriptStream(levels: nil)
            case .granite: stream = GraniteSpeechTranscriptStream()
            }
            capture = stream
            let token = gate.begin()
            let rawID = addTranscript(selected, status: "Starting")
            busy = true; status = "Preparing \(selected.rawValue)…"
            save()
            operation = Task {
                var ordered: [UUID] = []
                var texts: [UUID: String] = [:]
                let fallbackRequest = UUID()
                do {
                    try await stream.authorize(); try Task.checkCancellation()
                    try await stream.prime(); try Task.checkCancellation()
                    let updates = try await stream.start(audioURL: audioURL)
                    guard gate.accepts(token) else { throw CancellationError() }
                    recording = true; status = selected == .granite ? "Recording · Granite decodes after Stop." : "Recording…"
                    for await update in updates {
                        guard gate.accepts(token), !Task.isCancelled else { break }
                        if let issue = update.issue { error = issue }
                        // The legacy Granite adapter reports failures as bracketed text.
                        if selected == .granite && update.text.hasPrefix("[Granite Speech:") {
                            error = update.text
                            continue
                        }
                        let key = update.requestID ?? fallbackRequest
                        if !update.text.isEmpty {
                            if texts[key] == nil { ordered.append(key) }
                            texts[key] = update.text
                            updateRaw(rawID, text: ordered.compactMap { texts[$0] }.joined(separator: "\n"), status: "Recording / incomplete")
                            save()
                        }
                        if let termination = update.termination, termination != .finalized {
                            error = update.issue ?? "Recognition ended: \(termination.rawValue). Review partial text."
                        }
                    }
                    if gate.accepts(token) { finishRaw(rawID, status: error == nil ? "Completed" : "Incomplete — see error") }
                } catch { if gate.accepts(token) { self.error = error.localizedDescription; finishRaw(rawID, status: "Incomplete") } }
                await stream.stopImmediate(); await stream.unprime()
                if gate.accepts(token) { finishOperation() }
            }
        } catch { self.error = error.localizedDescription }
    }
    func stop() async {
        guard recording, let capture else { return }
        recording = false; status = "Finishing recognition; waiting for trailing audio…"
        await capture.stop()
    }
    func importAudio(_ url: URL) {
        guard !busy else { return }
        error = nil
        do {
            session.audioFilename = try store.importAudio(url)
            selectCurrentAudioSource()
            save()
            transcribeFile(useSelectedSource: false)
        }
        catch { self.error = "Audio import failed: \(error.localizedDescription)" }
    }
    func transcribeFile(useSelectedSource: Bool = true) {
        let sourceName = useSelectedSource ? sourceAudioFilename : session.audioFilename
        guard !busy, let name = sourceName else { return }
        guard session.asr.supportsFile else {
            error = "Parakeet file transcription is not implemented in this lab. Select Apple Speech or Granite explicitly, or use Parakeet live recording."; return
        }
        error = nil
        let selected = session.asr
        let token = gate.begin()
        let rawID = addTranscript(selected, status: "Transcribing file", audioFilename: name)
        let sessionID = session.id
        busy = true; status = "Transcribing saved audio with \(selected.rawValue)…"
        save()
        operation = Task {
            do {
                let url = try store.audioURL(name)
                if selected == .apple {
                    let authorization = await SpeechAuthorization.request()
                    guard authorization == .authorized else { throw TranscriptStreamError.speechDenied }
                    try Task.checkCancellation()
                    let completion = try await AppleSpeechFileTranscriber().transcribe(fileURL: url)
                    // Cancellation invalidates draft publication, not source evidence.
                    // Match the original session and row even after the run gate closes.
                    retainFileEvidence(completion, transcriptID: rawID, sessionID: sessionID)
                    if gate.accepts(token) {
                        error = completion.failureReason
                    }
                } else {
                    let runtime = GraniteSpeechRuntime(resolver: GraniteSpeechModelResolver(hfCacheLookup: { modelID in
                        HFHubCache.contains(modelId: modelID) ? HFHubCache.directory(for: modelID) : nil
                    }))
                    do {
                        try await runtime.prime(); try Task.checkCancellation()
                        let events = try await runtime.transcribe(audioURL: url)
                        var text = ""
                        for try await event in events {
                            try Task.checkCancellation()
                            if case .token(let token) = event { text += token }
                            if case .result(let result) = event, !result.text.isEmpty { text = result.text }
                            if gate.accepts(token) { updateRaw(rawID, text: text, status: "Transcribing / incomplete") }
                        }
                        if gate.accepts(token) { finishRaw(rawID, status: "Completed") }
                    } catch { await runtime.unload(); throw error }
                    await runtime.unload()
                }
            } catch { if gate.accepts(token) { self.error = error.localizedDescription; finishRaw(rawID, status: "Incomplete") } }
            if gate.accepts(token) { finishOperation() }
        }
    }
    func generate() {
        guard !busy, let raw = transcript, !raw.text.isEmpty else { return }
        error = nil
        let selected = session.llm, system = session.systemPrompt, task = session.taskPrompt
        let token = gate.begin()
        busy = true; status = "Generating separate \(selected.rawValue) draft…"
        operation = Task {
            do {
                let started = Date()
                // Fresh instance prevents a prior prompt's conversation from affecting comparisons.
                let backend = selected.makeBackend()
                let availability = await backend.availability
                guard availability == .available else { throw BackendError.generationFailed(availability.message(for: selected.rawValue)) }
                try Task.checkCancellation()
                let output = try await backend.generate(instructions: system, prompt: YapPreset.prompt(task: task, transcript: raw.text))
                guard gate.accepts(token), !Task.isCancelled else { return }
                session.results.append(YapResult(transcriptID: raw.id, backend: selected, systemPrompt: system, taskPrompt: task, text: output, elapsedSeconds: Date().timeIntervalSince(started)))
            } catch { if gate.accepts(token) { self.error = error.localizedDescription } }
            if gate.accepts(token) { finishOperation() }
        }
    }
    func cancel() async {
        guard busy else { save(); return }
        gate.cancel(); operation?.cancel(); recording = false
        status = "Cancelling; releasing audio and model resources…"
        if let capture { await capture.stopImmediate(); await capture.unprime() }
        await operation?.value
        if let last = session.transcripts.last, last.status.contains("ing") { finishRaw(last.id, status: "Cancelled / incomplete") }
        capture = nil; operation = nil; busy = false; status = "Cancelled. Retained transcript and prior results saved."; save()
    }
    private func addTranscript(_ backend: YapASR, status: String, audioFilename: String? = nil) -> UUID {
        let raw = YapTranscript(backend: backend, audioFilename: audioFilename ?? session.audioFilename, text: "", status: status)
        session.transcripts.append(raw); selectedTranscriptID = raw.id; return raw.id
    }
    func retainFileEvidence(_ completion: SpeechFileRunState.Completion, transcriptID: UUID, sessionID: UUID) {
        guard session.id == sessionID else { return }
        let status = completion.termination == .cancelled
            ? "Cancelled / incomplete" : (completion.isComplete ? "Completed" : "Incomplete")
        updateRaw(transcriptID, text: completion.transcript, status: status)
    }
    private func updateRaw(_ id: UUID, text: String, status: String) {
        guard let index = session.transcripts.firstIndex(where: { $0.id == id }) else { return }
        session.transcripts[index].text = text; session.transcripts[index].status = status
    }
    private func finishRaw(_ id: UUID, status: String) {
        guard let index = session.transcripts.firstIndex(where: { $0.id == id }) else { return }
        session.transcripts[index].status = status
    }
    private func finishOperation() {
        gate.cancel(); busy = false; recording = false; capture = nil; operation = nil
        status = error == nil ? "Finished. Raw recognition is preserved; drafts need review." : "Finished with an issue. Review retained evidence."
        save()
    }
}
