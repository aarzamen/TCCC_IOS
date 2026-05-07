import SwiftUI
import TCCCDomain

struct MedevacScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

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
            locationFix: state.locationFix
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
    }

    // MARK: - Panels

    private var nineLinePanel: some View {
        Panel("9-Line Format", action: completionAction, padded: false) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(form.entries) { entry in
                        NineLineRow(entry: entry)
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: Layout.hairline)
                    }
                }
            }
        }
    }

    private var completionAction: String {
        "\(form.completedCount) / \(form.totalCount) COMPLETE"
    }

    private var transmitPanel: some View {
        Panel("Voice Ready-Transmit", titleIcon: "antenna.radiowaves.left.and.right", padded: true) {
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
        state.appendSystem("REVIEW · 9-LINE FIELDS")
    }

    private func handleTransmit() {
        guard form.isReadyForTransmit else {
            state.appendSystem("TRANSMIT BLOCKED · 9-LINE INCOMPLETE · \(formattedTimestamp())")
            return
        }
        let dest = state.selectedHandoffDestination.displayName
        state.appendSystem("TRANSMIT · 9-LINE · \(dest) · \(formattedTimestamp())")
    }

    private func handleGenerate() {
        let snapshot = form
        let callsign = state.operatorCallsign
        // Snapshot patients + transcript on the main actor so the validator
        // can cross-check the SLM output against engine state.
        let patientsForValidation: [PatientState] = {
            let sorted = state.allPatients.values.sorted { $0.patientId < $1.patientId }
            if !sorted.isEmpty { return Array(sorted) }
            return state.primaryPatient.map { [$0] } ?? []
        }()
        let transcriptForValidation = state.transcript.map(\.text).joined(separator: " ")
        Task { @MainActor in
            isGenerating = true
            generationError = nil

            let backend = state.currentBackend
            // Pre-flight the selected backend so Generate cannot trigger an
            // implicit model download or show Apple-only availability text.
            let availability = await backend.availability
            guard availability == .available else {
                generationError = availability.message(for: backend.displayName)
                isGenerating = false
                return
            }

            do {
                let generator = RadioScriptGenerator(backend: backend)
                let text = try await generator.generate(
                    from: snapshot,
                    patients: patientsForValidation,
                    transcript: transcriptForValidation,
                    callsign: callsign
                )
                generatedScript = text
                state.appendSystem("RADIO SCRIPT · generated on-device · \(formattedTimestamp())")
            } catch {
                generationError = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func formattedTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
