import SwiftUI
import TCCCDomain

struct MedevacScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    private var form: NineLineForm {
        let patients = state.allPatients.values.sorted { $0.patientId < $1.patientId }
        let source: [PatientState] = patients.isEmpty
            ? state.primaryPatient.map { [$0] } ?? []
            : Array(patients)
        return NineLineForm.derive(
            from: source,
            gpsLatitude: state.gpsLatitude,
            gpsLongitude: state.gpsLongitude
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

                VStack(spacing: Layout.gridGap) {
                    mapPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    transmitPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(
                leadingLabel: "TCCC CARD",
                trailingLabel: "HANDOFF",
                onSettings: { state.settingsOpen = true },
                onQuickActions: { state.quickActionsOpen = true }
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

    private var mapPanel: some View {
        Panel("Grid · LZ", titleIcon: "mappin.and.ellipse", action: "UPDATING", padded: true) {
            MapPlotView()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 130)
        }
    }

    private var transmitPanel: some View {
        Panel("Voice Ready-Transmit", titleIcon: "antenna.radiowaves.left.and.right", padded: true) {
            TransmitScript(
                entries: form.entries,
                onReview: handleReview,
                onTransmit: handleTransmit
            )
        }
    }

    // MARK: - Actions

    private func handleReview() {
        state.appendSystem("REVIEW · 9-LINE FIELDS")
    }

    private func handleTransmit() {
        // Destination selection is owned by Screen 05 (Handoff). The actual
        // transport is hardware-deferred (RF Ghost forbids any radio call
        // from this codebase) — we record the action only.
        let dest = state.selectedHandoffDestination.displayName
        state.appendSystem("TRANSMIT · 9-LINE · \(dest) · \(formattedTimestamp())")
    }

    private func formattedTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
