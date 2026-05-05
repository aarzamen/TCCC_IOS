import SwiftUI

/// Per-element override stored by the playground.
///
/// All fields are optional. `nil` means "use the default" — the
/// component renders as if no override exists. The override only takes
/// effect for fields the user has explicitly touched.
public struct ElementOverride: Equatable, Sendable, Codable {
    public var isHidden: Bool?
    public var iconName: String?
    public var text: String?
    public var imageRef: ImageRef?
    public var width: CGFloat?
    public var height: CGFloat?
    public var cornerRadius: CGFloat?
    public var hiddenEdges: BorderEdges?

    public init(
        isHidden: Bool? = nil,
        iconName: String? = nil,
        text: String? = nil,
        imageRef: ImageRef? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat? = nil,
        hiddenEdges: BorderEdges? = nil
    ) {
        self.isHidden = isHidden
        self.iconName = iconName
        self.text = text
        self.imageRef = imageRef
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.hiddenEdges = hiddenEdges
    }

    public static let none = ElementOverride()

    public var hasAnyOverride: Bool {
        isHidden != nil
            || iconName != nil
            || text != nil
            || imageRef != nil
            || width != nil
            || height != nil
            || cornerRadius != nil
            || hiddenEdges != nil
    }
}

/// Reference to an image source. SF Symbols by name; custom images
/// stored as PNG bytes (base64-encoded in JSON for portability across
/// preset files).
public enum ImageRef: Equatable, Sendable, Codable {
    case sfSymbol(String)
    case asset(String)
    case custom(Data)
}

/// Per-edge border visibility. Empty set = all edges visible (default).
public struct BorderEdges: OptionSet, Equatable, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top      = BorderEdges(rawValue: 1 << 0)
    public static let bottom   = BorderEdges(rawValue: 1 << 1)
    public static let leading  = BorderEdges(rawValue: 1 << 2)
    public static let trailing = BorderEdges(rawValue: 1 << 3)

    public static let all: BorderEdges = [.top, .bottom, .leading, .trailing]
    public static let none: BorderEdges = []
}
