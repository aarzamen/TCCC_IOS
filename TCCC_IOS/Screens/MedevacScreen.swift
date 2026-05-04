import SwiftUI

struct MedevacScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .medevac,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "FORM",
                trailingKickerValue: "0 / 9"
            )

            HStack(spacing: Layout.gridGap) {
                Panel("9-Line Format", action: "0 / 9 COMPLETE", padded: false) {
                    PlaceholderBody(label: "Nine-line rows")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: Layout.gridGap) {
                    Panel("Grid · LZ", titleIcon: "mappin.and.ellipse", action: "—", padded: true) {
                        PlaceholderBody(label: "Map plot")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Panel("Voice Ready-Transmit", titleIcon: "antenna.radiowaves.left.and.right", padded: true) {
                        PlaceholderBody(label: "Call script + transmit")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(leadingLabel: "TCCC CARD", trailingLabel: "HANDOFF")
        }
        .background(palette.bg)
    }
}
