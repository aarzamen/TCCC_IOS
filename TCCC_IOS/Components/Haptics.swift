import UIKit

/// Centralized haptic feedback helpers.
///
/// Operator gloves are thick (CLAUDE.md hard constraint #4 — gloved-hand
/// input). When the medic does manage to land a tap, hold, swipe, or
/// transmit, they want a strong tactile confirmation that the device
/// registered the input. These wrappers prepare and fire generators in
/// one call so call sites stay readable.
///
/// - `tap(_:)`           - `UIImpactFeedbackGenerator` for taps + commits
///                         (default `.medium`; `.heavy` for hold-completes;
///                         `.light` for hold-starts and page-commit cues).
/// - `selection()`       - `UISelectionFeedbackGenerator` for radio toggles
///                         (LLM + ASR backend rows).
/// - `notify(_:)`        - `UINotificationFeedbackGenerator` for end-of-flow
///                         outcomes (`.success` / `.error` / `.warning`).
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
    }

    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
    }

    static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(kind)
    }
}
