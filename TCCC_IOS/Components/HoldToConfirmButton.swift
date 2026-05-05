import SwiftUI

/// Hold-to-confirm wrapper around `BigButton` for destructive actions per
/// CLAUDE.md hard constraint #4 ("Long-press only for destructive actions
/// with visual progress fill"). Mirrors the inline WIPE pattern in
/// `SettingsOverlay.sessionSection` so we have a single, reusable shape
/// for any future destructive control.
///
/// Why the local `DragGesture(minimumDistance: 0)` pattern instead of
/// `LongPressGesture`: SwiftUI's `LongPressGesture.onChanged` does NOT
/// fire continuously — it only fires once when the minimum duration is
/// reached. The WIPE button needs a smooth progress fill, so it polls
/// elapsed time on a 30 ms `Task.sleep` loop while a `DragGesture` keeps
/// the press alive. We replicate that here.
struct HoldToConfirmButton: View {
    let label: String
    let systemImage: String
    let style: BigButton.Style
    /// Hold duration in seconds. CLAUDE.md guidance: 2s for non-WIPE
    /// destructive actions; WIPE itself uses 3s.
    let holdSeconds: Double
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var progress: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Underlying BigButton renders the same visual shell. The
            // tap action is intentionally a no-op — only the gesture
            // below can fire `action`.
            BigButton(label, systemImage: systemImage, style: style, action: {})
                .gesture(holdGesture)

            // Progress fill — same dimensions / animation as WIPE.
            Rectangle()
                .fill(palette.crit)
                .frame(width: progress * 200, height: 2)
                .opacity(progress > 0 ? 1 : 0)
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard task == nil else { return }
                progress = 0
                // Subtle confirmation that the operator is holding the
                // right control. `.light` so it doesn't compete with the
                // `.heavy` impact that fires when the hold completes.
                Haptics.tap(.light)
                let start = Date()
                task = Task { @MainActor in
                    while !Task.isCancelled {
                        let elapsed = Date().timeIntervalSince(start)
                        let p = min(1, elapsed / holdSeconds)
                        progress = CGFloat(p)
                        if p >= 1 {
                            // Strong tactile commit when the action fires.
                            Haptics.tap(.heavy)
                            action()
                            progress = 0
                            task = nil
                            return
                        }
                        try? await Task.sleep(nanoseconds: 30_000_000)
                    }
                }
            }
            .onEnded { _ in
                task?.cancel()
                task = nil
                if progress < 1 {
                    withAnimation(.fast) {
                        progress = 0
                    }
                }
            }
    }
}
