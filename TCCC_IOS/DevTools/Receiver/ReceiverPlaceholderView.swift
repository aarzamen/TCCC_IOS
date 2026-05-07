import SwiftUI

struct ReceiverPlaceholderView: View {
    let onBack: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Panel("Receiver Mode", titleIcon: "antenna.radiowaves.left.and.right") {
                VStack(spacing: 14) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(palette.fg2)
                    Text("Receiver mode — coming soon")
                        .tccc(.h1)
                        .foregroundStyle(palette.fg)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
            .frame(maxWidth: 520)

            BigButton("Back", systemImage: "chevron.left", action: onBack)
                .frame(maxWidth: 260)

            Spacer(minLength: 0)
        }
        .padding(Layout.outerPadding)
    }
}
