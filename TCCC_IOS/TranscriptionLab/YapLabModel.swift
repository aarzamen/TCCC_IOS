import Foundation
import Observation
import Speech
import AVFAudio
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
    var saveError: String?
    var lastSavedAt: Date?
    var readiness = "Check models to inspect availability."
    var unreadableSessionCount = 0
    var speechPermission = SFSpeechRecognizer.authorizationStatus()
    var microphoneDenied = AVAudioApplication.shared.recordPermission == .denied
    private let store: YapLabStore
    private var gate = YapRunGate()
    private var operation: Task<Void, Never>?
    private var capture: (any TranscriptStream)?
    private var lastPartialCheckpoint: ContinuousClock.Instant?

    init(store: YapLabStore = YapLabStore()) { self.store = store }
    var permissionGuidance: String? {
        var messages: [String] = []
        if microphoneDenied { messages.append("Microphone access is off. Enable it in Settings to record; audio import remains available.") }
        if session.asr == .apple {
            if speechPermission == .denied {
                messages.append("Apple Speech access is off. Enable Speech Recognition in Settings, or choose another recognizer.")
            } else if speechPermission == .restricted {
                messages.append("Apple Speech is restricted on this device. Choose another recognizer.")
            }
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
    var canOpenPermissionSettings: Bool {
        microphoneDenied || (session.asr == .apple && speechPermission == .denied)
    }
    func refreshPermissions() {
        speechPermission = SFSpeechRecognizer.authorizationStatus()
        microphoneDenied = AVAudioApplication.shared.recordPermission == .denied
    }
    var transcript: YapTranscript? {
        session.transcripts.first { $0.id == selectedTranscriptID }
            ?? session.transcripts.last { $0.audioFilename == session.audioFilename }
    }
    var sourceAudioFilename: String? {
        if let selectedTranscriptID,
           let selected = session.transcripts.first(where: { $0.id == selectedTranscriptID }) {
            return selected.audioFilename
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
            if let reason = raw.failureReason { parts.append("RECOGNITION ISSUE · \(reason)") }
            for result in session.results where result.transcriptID == raw.id {
                parts.append("DRAFT · \(result.backend.rawValue)\nSYSTEM: \(result.systemPrompt)\nTASK: \(result.taskPrompt)\n\(result.text)")
            }
        }
        return parts.joined(separator: "\n\n")
    }
    func refresh() {
        do {
            let inventory = try store.inventory()
            saved = inventory.sessions
            unreadableSessionCount = inventory.unreadableCount
        } catch { self.error = "Saved sessions could not be read: \(error.localizedDescription)" }
    }
    @discardableResult
    func save(refreshLibrary: Bool = true) -> Bool {
        do {
            try store.save(session)
            saveError = nil
            lastSavedAt = Date()
            if refreshLibrary { refresh() }
            return true
        } catch {
            saveError = "Session save failed: \(error.localizedDescription) Your current evidence is still in memory. Retry Save before leaving."
            return false
        }
    }
    func newSession() {
        guard !busy else { return }
        error = nil
        guard save() else { return }
        session = YapLabSession(); selectedTranscriptID = nil; lastSavedAt = nil; status = "New session."
    }
    func reopen(_ id: UUID) {
        guard !busy else { return }
        error = nil
        guard save() else { return }
        do {
            var reopened = try store.load(id)
            reopened.recoverInterruptedTranscripts()
            session = reopened
            selectCurrentAudioSource()
            status = "Saved session reopened."
            save()
        }
        catch { self.error = error.localizedDescription }
    }
    func apply(_ preset: YapPreset) { session.systemPrompt = preset.system; session.taskPrompt = preset.task }
    func checkReadiness() async {
        refreshPermissions()
        let selected = session.llm
        let availability = await selected.makeBackend().availability
        guard selected == session.llm else { return }
        let speech = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let appleReady = speech?.isAvailable == true && speech?.supportsOnDeviceRecognition == true
        let parakeetReady = OfflineModelAssets.parakeetDirectory != nil
        let speechAccess = speechPermission == .authorized ? "permission granted" : "check permission before use"
        readiness = "Parakeet local files: \(parakeetReady ? "installed" : "missing"). Apple Speech: \(appleReady ? "on-device supported; \(speechAccess)" : "unavailable"). \(selected.rawValue): \(availability == .available ? "assets available" : availability.message(for: selected.rawValue)) Alternate ASR requires installed assets; Parakeet supports live capture here, Granite transcribes after Stop."
    }
    func record(clinicalRecording: Bool) {
        guard !busy else { return }
        guard !clinicalRecording else { error = "End clinical recording before opening a lab microphone."; return }
        error = nil
        do {
            try store.prepare()
            let name = UUID().uuidString + ".m4a"
            let priorSource = session.audioFilename
            let priorSelection = selectedTranscriptID
            session.audioFilename = name
            let audioURL = try store.audioURL(name)
            let selected = session.asr
            let stream: any TranscriptStream
            switch selected {
            case .apple: stream = SpeechRecognizer(levels: nil)
            case .parakeet: stream = ParakeetTranscriptStream(levels: nil)
            case .granite: stream = GraniteSpeechTranscriptStream()
            }
            let rawID = addTranscript(selected, status: "Starting")
            guard checkpoint(rawID) else {
                session.audioFilename = priorSource
                selectedTranscriptID = priorSelection
                // No recorder opened this path. Retain the failed attempt,
                // but do not link it to an audio file that was never created.
                session.transcripts[session.transcripts.count - 1].audioFilename = nil
                return
            }
            capture = stream
            let token = gate.begin()
            busy = true; status = "Preparing \(selected.rawValue)…"
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
                            guard checkpointPartialEvidence() else { throw BackendError.generationFailed(saveError ?? "Evidence could not be saved.") }
                        }
                        if let termination = update.termination, termination != .finalized {
                            error = update.issue ?? "Recognition ended: \(termination.rawValue). Review partial text."
                        }
                    }
                    if gate.accepts(token) { finishRaw(rawID, status: error == nil ? "Completed" : "Incomplete", failureReason: error) }
                } catch { if gate.accepts(token) { self.error = error.localizedDescription; finishRaw(rawID, status: "Incomplete", failureReason: error.localizedDescription) } }
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
            guard save() else { return }
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
        let rawID = addTranscript(selected, status: "Transcribing file", audioFilename: name)
        guard checkpoint(rawID) else { return }
        let token = gate.begin()
        let sessionID = session.id
        busy = true; status = "Transcribing saved audio with \(selected.rawValue)…"
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
                        error = session.transcripts.first(where: { $0.id == rawID })?.failureReason
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
                            if gate.accepts(token) {
                                updateRaw(rawID, text: text, status: "Transcribing / incomplete")
                                guard checkpointPartialEvidence() else { throw BackendError.generationFailed(saveError ?? "Evidence could not be saved.") }
                            }
                        }
                        if gate.accepts(token) { finishRaw(rawID, status: "Completed") }
                    } catch { await runtime.unload(); throw error }
                    await runtime.unload()
                }
            } catch { if gate.accepts(token) { self.error = error.localizedDescription; finishRaw(rawID, status: "Incomplete", failureReason: error.localizedDescription) } }
            if gate.accepts(token) { finishOperation() }
        }
    }
    func generate() {
        guard !busy, let raw = transcript, !raw.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        error = nil
        guard save() else { return }
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
                guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BackendError.generationFailed("The model returned no draft text. Your source is unchanged; try another prompt or model.")
                }
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
        if let last = session.transcripts.last, last.isInProgress {
            finishRaw(last.id, status: "Cancelled / incomplete", failureReason: error ?? "Transcription stopped before completion.")
        }
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
        finishRaw(transcriptID, status: status, failureReason: completion.failureReason)
    }
    private func updateRaw(_ id: UUID, text: String, status: String) {
        guard let index = session.transcripts.firstIndex(where: { $0.id == id }) else { return }
        session.transcripts[index].text = text; session.transcripts[index].status = status
    }
    private func finishRaw(_ id: UUID, status: String, failureReason: String? = nil) {
        guard let index = session.transcripts.firstIndex(where: { $0.id == id }) else { return }
        let emptyCompletion = status == "Completed"
            && session.transcripts[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        session.transcripts[index].status = emptyCompletion ? "No speech recognized" : status
        session.transcripts[index].failureReason = emptyCompletion
            ? "The recognizer ended without returning words. Listen to the source and try another recognizer; finalization alone does not prove speech coverage."
            : failureReason
        if emptyCompletion { error = session.transcripts[index].failureReason }
    }
    private func checkpointPartialEvidence() -> Bool {
        // Persist partial evidence without rescanning every saved session for
        // each token. Normal completion/cancellation still saves immediately.
        let now = ContinuousClock.now
        if let lastPartialCheckpoint, now - lastPartialCheckpoint < .seconds(1) { return true }
        guard save(refreshLibrary: false) else { return false }
        lastPartialCheckpoint = now
        return true
    }
    private func checkpoint(_ rawID: UUID) -> Bool {
        lastPartialCheckpoint = nil
        guard save() else {
            finishRaw(rawID, status: "Not started", failureReason: saveError)
            status = "Not started. Save the session successfully before retrying."
            return false
        }
        return true
    }
    private func finishOperation() {
        gate.cancel(); busy = false; recording = false; capture = nil; operation = nil
        status = error == nil ? "Finished. Raw recognition is preserved; drafts need review." : "Finished with an issue. Review retained evidence."
        save()
        refreshPermissions()
    }
}
