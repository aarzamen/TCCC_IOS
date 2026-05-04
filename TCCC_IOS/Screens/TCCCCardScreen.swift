import SwiftUI

struct TCCCCardScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .tcccCard,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "STATUS",
                trailingKickerValue: "DRAFT"
            )

            HStack(spacing: Layout.gridGap) {
                Panel("Casualty · \(state.casualtyId)", action: "—", padded: false) {
                    PlaceholderBody(label: "Patient header + body map")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Panel("M.A.R.C.H.", action: "ASSESSMENT", padded: false) {
                    PlaceholderBody(label: "MARCH rows")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: Layout.gridGap) {
                    Panel("P.A.W.S.", padded: false) {
                        PlaceholderBody(label: "PAWS rows")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Panel("Meds Log", titleIcon: "syringe", padded: false) {
                        PlaceholderBody(label: "Meds log")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(leadingLabel: "VITALS", trailingLabel: "MEDEVAC")
        }
        .background(palette.bg)
    }
}
