import SwiftUI

struct LiveCaptureScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .liveCapture,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "LAST READING",
                trailingKickerValue: "00:00:42 AGO"
            )

            HStack(spacing: Layout.gridGap) {
                Panel("Transcript", titleIcon: "mic", action: "● LIVE", padded: false) {
                    PlaceholderBody(label: "Transcript stream")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Panel("Capture", titleIcon: "record.circle", padded: true) {
                    PlaceholderBody(label: "Audio + voice commands")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Panel("Extracted", action: "0", padded: false) {
                    PlaceholderBody(label: "Auto-extracted facts")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(leadingLabel: "HANDOFF", trailingLabel: "VITALS")
        }
        .background(palette.bg)
    }
}
