import SwiftUI
import Speech
import FoundationModels

/// Read-only readiness inspection. Preparation happens explicitly on the install Mac.
/// A build with OfflineModels embedded works on a new install without warming caches.
struct OfflineModelPreparationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ModelRow] = []
    @State private var appleSpeech = "Checking…"
    @State private var appleLanguage = "Checking…"
    @State private var checking = false

    private struct ModelRow: Identifiable, Sendable {
        let id: String
        let location: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Offline model preparation").font(.title2.bold())
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered).frame(minWidth: 64, minHeight: 44)
                }
                Text("Local files are checked before inference. File readiness does not prove accuracy or successful model execution.")
                HStack {
                    Button(checking ? "Checking…" : "Refresh local checks") { refresh() }
                        .buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(checking)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple system assets").font(.headline)
                    Text("Speech: \(appleSpeech)")
                    Text("Foundation Models: \(appleLanguage)")
                    Text("Apple manages these assets separately. Enable Apple Intelligence and finish system downloads before going offline; an app installation cannot preload them.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.id).font(.headline).textSelection(.enabled)
                        Text(row.location == nil ? "MISSING OR INCOMPLETE" : "LOCAL FILES READY")
                            .foregroundStyle(row.location == nil ? Color.orange : Color.green)
                        if let location = row.location {
                            DisclosureGroup("Installation details") {
                                Text(location).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                Divider()
                Text("Prepare a new field install").font(.headline)
                Text("Use the Mac staging tool to download the pinned model set and verify hashes. Build with TCCC_OFFLINE_MODELS_DIR pointing to the staged OfflineModels folder. The signed app then carries its own models. Existing installs can also receive the same folder in Documents/OfflineModels through USB file sharing.")
                Text("Missing alternate ASR/LLM assets block those backends. TTS can use its labeled Device Speech fallback. Settings Download is explicit online preparation; recording and generation use local assets.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24)
        }.task { refresh() }
    }

    private func refresh() {
        guard !checking else { return }
        checking = true
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        appleSpeech = recognizer?.supportsOnDeviceRecognition == true
            ? "On-device recognition supported; microphone/speech permission and a live offline test still required"
            : "On-device recognition unavailable"
        switch SystemLanguageModel.default.availability {
        case .available: appleLanguage = "Available on this device"
        case .unavailable(let reason): appleLanguage = "Unavailable: \(String(describing: reason))"
        @unknown default: appleLanguage = "Unknown system state"
        }
        Task {
            rows = await Task.detached(priority: .utility) {
                OfflineModelAssets.modelIDs.map { id in
                    ModelRow(id: id, location: OfflineModelAssets.resolve(modelID: id)?.path)
                }
            }.value
            checking = false
        }
    }
}
