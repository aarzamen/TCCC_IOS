import SwiftUI

enum Theme: String, CaseIterable, Sendable, Codable, Identifiable {
    case tactical
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tactical: "Tactical"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var palette: Palette {
        switch self {
        case .tactical: .tactical
        case .dark: .dark
        case .light: .light
        }
    }

    var preferredColorScheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

struct Palette: Sendable {
    let bg: Color
    let bg1: Color
    let bg2: Color
    let bg3: Color
    let line: Color
    let lineStrong: Color
    let fg: Color
    let fg1: Color
    let fg2: Color
    let fg3: Color
    let accent: Color
    let accentDim: Color
    let accentHot: Color
    let crit: Color
    let warn: Color
    let ok: Color
    let rec: Color
    let grid: Color
}

extension Palette {
    static let tactical = Palette(
        bg:           Color(hex: 0x080302),
        bg1:          Color(hex: 0x110604),
        bg2:          Color(hex: 0x1a0907),
        bg3:          Color(hex: 0x240d0a),
        line:         Color(hex: 0x3a1108),
        lineStrong:   Color(hex: 0x5a1a0e),
        fg:           Color(hex: 0xe8c4bc),
        fg1:          Color(hex: 0xc89890),
        fg2:          Color(hex: 0x8a564f),
        fg3:          Color(hex: 0x5a3530),
        accent:       Color(hex: 0xd63a1f),
        accentDim:    Color(hex: 0x8a2412),
        accentHot:    Color(hex: 0xff4a26),
        crit:         Color(hex: 0xff4a26),
        warn:         Color(hex: 0xd4870f),
        ok:           Color(hex: 0x6a8a3a),
        rec:          Color(hex: 0xff2d12),
        grid:         Color(hex: 0x1a0805)
    )

    static let dark = Palette(
        bg:           Color(hex: 0x0a0b0d),
        bg1:          Color(hex: 0x111317),
        bg2:          Color(hex: 0x181b21),
        bg3:          Color(hex: 0x20242c),
        line:         Color(hex: 0x2a2f38),
        lineStrong:   Color(hex: 0x3a4150),
        fg:           Color(hex: 0xf0f2f5),
        fg1:          Color(hex: 0xb8bdc7),
        fg2:          Color(hex: 0x7a818d),
        fg3:          Color(hex: 0x4a505a),
        accent:       Color(hex: 0xff8a3d),
        accentDim:    Color(hex: 0x8a4a1f),
        accentHot:    Color(hex: 0xffa566),
        crit:         Color(hex: 0xff3b2f),
        warn:         Color(hex: 0xffb020),
        ok:           Color(hex: 0x3fb950),
        rec:          Color(hex: 0xff3b2f),
        grid:         Color(hex: 0x15181d)
    )

    static let light = Palette(
        bg:           Color(hex: 0xe8e6e0),
        bg1:          Color(hex: 0xddd9d0),
        bg2:          Color(hex: 0xcfcabe),
        bg3:          Color(hex: 0xb8b2a2),
        line:         Color(hex: 0x6a6356),
        lineStrong:   Color(hex: 0x2a2620),
        fg:           Color(hex: 0x0a0807),
        fg1:          Color(hex: 0x3a342c),
        fg2:          Color(hex: 0x6a6356),
        fg3:          Color(hex: 0x8a8278),
        accent:       Color(hex: 0xb8341a),
        accentDim:    Color(hex: 0x7a1f10),
        accentHot:    Color(hex: 0xd63a1f),
        crit:         Color(hex: 0xb8341a),
        warn:         Color(hex: 0x8a5510),
        ok:           Color(hex: 0x3a6a1a),
        rec:          Color(hex: 0xb8341a),
        grid:         Color(hex: 0xd0ccc0)
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .tactical
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
