import SwiftUI
import TCCCDomain

struct MedevacScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    @State private var generationTask: Task<Void, Never>?
    @State private var showRadioConfirmation = false
    @State private var radioError: String?
    @State private var generatedScript: String?
    @State private var isGenerating: Bool = false
    @State private var generationError: String?

    private var form: NineLineForm {
        let patients = state.allPatients.values.sorted { $0.patientId < $1.patientId }
        let source: [PatientState] = patients.isEmpty
            ? state.primaryPatient.map { [$0] } ?? []
            : Array(patients)
        return NineLineForm.derive(
            from: source,
            locationFix: state.locationFix,
            operatorValues: state.nineLineValues
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .medevac,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "FORM",
                trailingKickerValue: "\(form.completedCount) / \(form.totalCount)"
            )

            HStack(spacing: Layout.gridGap) {
                nineLinePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                transmitPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(
                state: state,
                leadingLabel: "TCCC CARD",
                trailingLabel: "HANDOFF"
            )
        }
        .background(palette.bg)
        .onChange(of: generationContext) { _, _ in
            generationTask?.cancel(); generationTask = nil
            generatedScript = nil; generationError = nil; isGenerating = false
        }
        .onDisappear { generationTask?.cancel(); isGenerating = false }
        .confirmationDialog("Record that you made the radio call?", isPresented: $showRadioConfirmation, titleVisibility: .visible) {
            Button("I made the radio call") {
                let encounter = state.encounterIdentity
                Task {
                    var metadata = state.operatorMetadata
                    metadata.radioCallTime = Date()
                    metadata.notes.append(.init(timestamp: Date(), text: "RADIO CALL · operator confirmed"))
                    do { try await state.saveOperatorMetadata(metadata, encounter: encounter) }
                    catch { radioError = error.localizedDescription }
                }
            }
        } message: { Text("This app does not transmit a radio request. Only record a call you actually made.") }
        .alert("Could not save radio-call time", isPresented: Binding(get: { radioError != nil }, set: { if !$0 { radioError = nil } })) {
            Button("OK") { radioError = nil }
        } message: { Text(radioError ?? "") }
    }

    // MARK: - Panels

    private var nineLinePanel: some View {
        Panel("9-Line Format", action: completionAction, padded: false) {
            VStack(spacing: 0) {
                gpsCaptureBar
                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(form.entries) { entry in
                            NineLineRow(entry: entry, onEdit: { state.clinicalEntrySheet = .nineLine })
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: Layout.hairline)
                        }
                    }
                }
            }
        }
    }

    /// LINE 1 capture control. The only runtime location source is the real
    /// iPhone GPS (operator-gated one-shot). Status label and color reflect
    /// `state.locationStatus`; primary action is gloved-hand sized (≥56 pt).
    private var gpsCaptureBar: some View {
        let requesting = state.locationStatus == .requesting
        return HStack(spacing: 12) {
            Image(systemName: gpsStatusIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(gpsStatusColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("LINE 1 · GPS")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(palette.fg2)
                Text(gpsStatusLabel)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(gpsStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Button {
                Task { await state.captureGPSFix() }
            } label: {
                Text(requesting ? "…" : "USE GPS FIX")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(requesting ? palette.fg3 : palette.bg)
                    .frame(minWidth: 132, minHeight: 56)
                    .background(requesting ? palette.fg3.opacity(0.25) : palette.accent)
            }
            .disabled(requesting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var gpsStatusLabel: String {
        switch state.locationStatus {
        case .noFix:                          "NO FIX"
        case .requesting:                     "REQUESTING GPS"
        case .fix(let acc):                   "GPS FIX\(accuracySuffix(acc))"
        case .degraded(let acc):              "GPS DEGRADED\(accuracySuffix(acc))"
        case .denied:                         "GPS DENIED — enable Location in iOS Settings"
        case .restricted:                     "GPS RESTRICTED"
        case .mgrsUnavailable:                "MGRS UNAVAILABLE"
        }
    }

    private func accuracySuffix(_ meters: Double?) -> String {
        guard let m = meters, m >= 0 else { return "" }
        return " ± \(Int(m.rounded()))m"
    }

    private var gpsStatusColor: Color {
        switch state.locationStatus {
        case .fix:                       palette.accent
        case .requesting:                palette.fg2
        case .degraded:                  palette.warn
        case .noFix, .denied,
             .restricted, .mgrsUnavailable: palette.crit
        }
    }

    private var gpsStatusIcon: String {
        switch state.locationStatus {
        case .fix:          "location.fill"
        case .requesting:   "location.circle"
        case .degraded:     "location.slash"
        case .noFix, .denied, .restricted, .mgrsUnavailable: "exclamationmark.triangle.fill"
        }
    }

    private var completionAction: String {
        "\(form.completedCount) / \(form.totalCount) COMPLETE"
    }

    private var transmitPanel: some View {
        Panel("Radio call worksheet", titleIcon: "antenna.radiowaves.left.and.right", padded: true) {
            VStack(spacing: 8) {
                // Persistent SLM availability badge — operator sees current
                // truth before tapping Generate. Per night-pass A5.
                HStack(spacing: 0) {
                    FMStatusBadge(state: state)
                    Spacer()
                }
                TransmitScript(
                    entries: form.entries,
                    onReview: handleReview,
                    onTransmit: handleTransmit,
                    onGenerate: handleGenerate,
                    generatedScript: generatedScript,
                    isGenerating: isGenerating,
                    generationError: generationError
                )
            }
        }
    }

    // MARK: - Actions

    private func handleReview() {
        state.clinicalEntrySheet = .nineLine
    }

    private func handleTransmit() { showRadioConfirmation = true }

    private var generationContext: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let patients = (try? encoder.encode(state.allPatients)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return state.encounterIdentity.uuidString + form.entries.map(\.value).joined(separator: "|")
            + state.operatorCallsign + state.llmBackend.rawValue + patients
            + state.transcript.map(\.text).joined(separator: "|")
    }

    private func handleGenerate() {
        generationTask?.cancel()
        let context = generationContext
        let snapshot = form
        let patients = state.allPatients.values.sorted { $0.patientId < $1.patientId }
        let transcript = state.transcript.map(\.text).joined(separator: " ")
        let callsign = state.operatorCallsign
        let backend = state.currentBackend
        isGenerating = true; generationError = nil
        generationTask = Task { @MainActor in
            let availability = await backend.availability
            guard !Task.isCancelled, generationContext == context else { return }
            guard availability == .available else {
                generationError = availability.message(for: backend.displayName)
                isGenerating = false; return
            }
            do {
                let text = try await RadioScriptGenerator(backend: backend).generate(
                    from: snapshot, patients: Array(patients), transcript: transcript, callsign: callsign)
                guard !Task.isCancelled, generationContext == context else { return }
                generatedScript = text
            } catch {
                guard !Task.isCancelled, generationContext == context else { return }
                generationError = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
