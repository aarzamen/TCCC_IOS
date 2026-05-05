import Foundation

/// Stable identifier for an editable UI element.
///
/// Every element the playground can edit (a panel, a heading, an icon
/// slot, a frame) is wrapped in a `.playgroundEditable(.someID)`
/// modifier. The ID flows through the override store so the same edit
/// survives app restarts and bakes correctly to source.
///
/// The identifier is structured as `screen / category / slot` to make
/// the inspector's per-screen filtering trivial. Add new cases freely;
/// each case is a contract between a component and the playground.
public struct ElementID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let screen: Screen
    public let category: Category
    public let slot: String

    public enum Screen: String, Hashable, Sendable, Codable, CaseIterable {
        case global
        case liveCapture
        case vitals
        case tcccCard
        case medevac
        case handoff
    }

    public enum Category: String, Hashable, Sendable, Codable, CaseIterable {
        case statusStrip
        case pageHeader
        case panel
        case panelTitle
        case panelIcon
        case panelBorder
        case bigVital
        case smallVital
        case bodyMap
        case ecg
        case trendChart
        case mapPlot
        case footerHints
        case button
        case image
        case other
    }

    public init(screen: Screen, category: Category, slot: String) {
        self.screen = screen
        self.category = category
        self.slot = slot
    }

    public var description: String {
        "\(screen.rawValue).\(category.rawValue).\(slot)"
    }

    // MARK: - Convenience builders for the most common slots

    public static func statusStrip(_ slot: String) -> ElementID {
        ElementID(screen: .global, category: .statusStrip, slot: slot)
    }

    public static func footerHints(_ slot: String) -> ElementID {
        ElementID(screen: .global, category: .footerHints, slot: slot)
    }

    public static func pageHeader(_ screen: Screen) -> ElementID {
        ElementID(screen: screen, category: .pageHeader, slot: "main")
    }

    public static func panel(_ screen: Screen, _ slot: String) -> ElementID {
        ElementID(screen: screen, category: .panel, slot: slot)
    }
}
