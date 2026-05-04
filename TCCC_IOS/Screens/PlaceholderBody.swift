import SwiftUI

struct PlaceholderBody: View {
    let label: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .tccc(.labelSmall)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            Text("Phase pending")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
