import SwiftUI

/// Meaning of a caller-supplied visual status. Colors never infer clinical assessment.
public enum SemanticRole: String, CaseIterable, Sendable {
    case accent, ai, ok, warn, danger, muted, ink, dim
}

/// Exact sRGB channels kept independent of display conversion for token verification.
public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

public struct ThemePalette: Equatable, Sendable {
    public let background, panel, panel2, line: ThemeColor
    public let ink, muted, dim: ThemeColor
    public let accent, ai, ok, warn, danger: ThemeColor

    public subscript(_ role: SemanticRole) -> ThemeColor {
        switch role {
        case .accent: accent
        case .ai: ai
        case .ok: ok
        case .warn: warn
        case .danger: danger
        case .muted: muted
        case .ink: ink
        case .dim: dim
        }
    }
}

/// Operator-selected palette; no automatic switching or hardware/night-vision claims.
public struct Theme: Equatable, Sendable {
    public let palette: ThemePalette
    public var gloveMode: Bool = false

    public static let base = Theme(palette: ThemePalette(
        background: ThemeColor(hex: 0x0B0D10), panel: ThemeColor(hex: 0x141820),
        panel2: ThemeColor(hex: 0x1B2029), line: ThemeColor(hex: 0x2A303A),
        ink: ThemeColor(hex: 0xE6E8EB), muted: ThemeColor(hex: 0x8A93A0), dim: ThemeColor(hex: 0x5B6470),
        // Exact HSL(27°, 88%, 56%) conversion, without rounding to 8-bit RGB.
        accent: ThemeColor(red: 0.9472, green: 0.52128, blue: 0.1728),
        ai: ThemeColor(hex: 0x59C3E8), ok: ThemeColor(hex: 0x4CC38A),
        warn: ThemeColor(hex: 0xE8B44C), danger: ThemeColor(hex: 0xE5484D)
    ))
    public static let night = Theme(palette: ThemePalette(
        background: ThemeColor(hex: 0x070404), panel: ThemeColor(hex: 0x120909),
        panel2: ThemeColor(hex: 0x1A0C0C), line: ThemeColor(hex: 0x3A1A1A),
        ink: ThemeColor(hex: 0xE0A070), muted: ThemeColor(hex: 0x9A6A4A), dim: ThemeColor(hex: 0x5A3A2A),
        accent: ThemeColor(hex: 0xFF5A3A), ai: ThemeColor(hex: 0xD89A6A),
        ok: ThemeColor(hex: 0xC88A50), warn: ThemeColor(hex: 0xE0A050), danger: ThemeColor(hex: 0xFF4A3A)
    ))

    public func color(_ role: SemanticRole) -> Color { palette[role].color }

    public func withGloveMode(_ enabled: Bool = true) -> Theme {
        var theme = self
        theme.gloveMode = enabled
        return theme
    }
}

private struct TCCCThemeKey: EnvironmentKey {
    static let defaultValue = Theme.base
}

extension EnvironmentValues {
    public var tcccTheme: Theme {
        get { self[TCCCThemeKey.self] }
        set { self[TCCCThemeKey.self] = newValue }
    }
}

public enum ActionButtonSize: String, CaseIterable, Sendable { case small, medium, large }

/// Scalable lower bounds; text and layout are allowed to grow beyond these sizes.
public struct ThemeMetrics: Equatable, Sendable {
    public let gloveMode: Bool
    public let scale: Double

    public init(gloveMode: Bool = false, scale: Double = 1) {
        self.gloveMode = gloveMode
        self.scale = scale.isFinite ? max(1, scale) : 1
    }

    public var tap: CGFloat { (gloveMode ? 60 : 44) * scale }
    public var row: CGFloat { (gloveMode ? 64 : 52) * scale }
    public func buttonHeight(_ size: ActionButtonSize) -> CGFloat {
        size == .large ? tap + 12 * scale : tap
    }
}

/// Use as `@DesignMetrics private var metrics` in package or caller views.
@propertyWrapper
public struct DesignMetrics: DynamicProperty {
    @Environment(\.tcccTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    public init() {}
    public var wrappedValue: ThemeMetrics { ThemeMetrics(gloveMode: theme.gloveMode, scale: scale) }
}
