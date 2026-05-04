import SwiftUI

struct PageIndicator: View {
    let count: Int
    let active: Int
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index == active ? palette.accent : palette.fg3)
                    .frame(width: index == active ? 18 : 8, height: 3)
                    .animation(.standard, value: active)
            }
        }
    }
}
