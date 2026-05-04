import SwiftUI

struct VitalsScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .vitals,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "LAST UPDATE",
                trailingKickerValue: "—"
            )

            HStack(spacing: Layout.gridGap) {
                VStack(spacing: Layout.gridGap) {
                    Panel("ECG · Lead II", titleIcon: "waveform.path.ecg", action: "—", padded: true) {
                        PlaceholderBody(label: "ECG waveform")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: Layout.gridGap) {
                    Panel("Trend · Last 15 Min", titleIcon: "chart.xyaxis.line", action: "HR · BP · SpO₂", padded: true) {
                        PlaceholderBody(label: "Trend chart")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Panel("Interventions", action: "0 LOGGED", padded: false) {
                        PlaceholderBody(label: "Interventions log")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(leadingLabel: "CAPTURE", trailingLabel: "TCCC CARD")
        }
        .background(palette.bg)
    }
}
