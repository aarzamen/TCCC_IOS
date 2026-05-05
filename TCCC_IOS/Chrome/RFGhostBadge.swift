import SwiftUI

struct RFGhostBadge: View {
    let state: AppState.RFState
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.0)
                .foregroundStyle(iconColor)
                .modifier(BlinkIfLeak(isLeak: state == .leak))
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(
            state == .leak
                ? palette.bg2
                : Color.clear
        )
    }

    private var label: String {
        switch state {
        case .ghost: "OFFLINE"
        case .burst: "BURST"
        case .leak:  "LEAK"
        }
    }

    private var iconColor: Color {
        switch state {
        case .ghost: palette.accent
        case .burst: palette.warn
        case .leak:  palette.crit
        }
    }
}

private struct BlinkIfLeak: ViewModifier {
    let isLeak: Bool
    @State private var visible: Bool = true

    func body(content: Content) -> some View {
        content
            .opacity(isLeak ? (visible ? 1 : 0.2) : 1)
            .task(id: isLeak) {
                guard isLeak else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    visible.toggle()
                }
            }
    }
}
