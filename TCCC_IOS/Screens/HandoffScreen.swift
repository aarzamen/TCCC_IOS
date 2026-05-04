import SwiftUI

struct HandoffScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .handoff,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "DESTINATION",
                trailingKickerValue: "—"
            )

            HStack(spacing: Layout.gridGap) {
                Panel("Encounter Summary", titleIcon: "doc.text", action: state.casualtyId, padded: false) {
                    PlaceholderBody(label: "Encounter summary")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Panel("Timeline", titleIcon: "clock", action: "—", padded: false) {
                    PlaceholderBody(label: "Event timeline")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Panel("Export · Transmit", titleIcon: "square.and.arrow.up", padded: true) {
                    PlaceholderBody(label: "Export targets + transmit")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(leadingLabel: "MEDEVAC", trailingLabel: nil)
        }
        .background(palette.bg)
    }
}
