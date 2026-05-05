import UIKit

/// Centralized haptic feedback helpers.
///
/// Operator gloves are thick (CLAUDE.md hard constraint #4 — gloved-hand
/// input). When the medic does manage to land a tap, hold, swipe, or
/// transmit, they want a strong tactile confirmation that the device
/// registered the input.
///
/// Generators are retained as static instances and `prepare()`-pumped
/// after each fire so the next event has the actuator pre-warmed —
/// fresh-instance-per-call leaves a ~150 ms warmup cost that empirically
/// drops the first haptic on iPhone 17 Pro under iOS 26.x.
@MainActor
enum Haptics {
    private static var lightGen = UIImpactFeedbackGenerator(style: .light)
    private static var mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static var heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static var selectionGen = UISelectionFeedbackGenerator()
    private static var notifyGen = UINotificationFeedbackGenerator()

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let gen: UIImpactFeedbackGenerator
        switch style {
        case .light:  gen = lightGen
        case .medium: gen = mediumGen
        case .heavy:  gen = heavyGen
        @unknown default: gen = mediumGen
        }
        gen.impactOccurred()
        gen.prepare()
    }

    static func selection() {
        selectionGen.selectionChanged()
        selectionGen.prepare()
    }

    static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        notifyGen.notificationOccurred(kind)
        notifyGen.prepare()
    }
}
