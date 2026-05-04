import SwiftUI

enum TypeStyle {
    case label
    case labelSmall
    case labelTiny
    case meta
    case bodyText
    case transcript
    case nineLineValue
    case bigVital
    case smallVital
    case h1
    case timer
}

extension Text {
    func tccc(_ style: TypeStyle) -> Text {
        switch style {
        case .label:
            return self
                .font(.system(size: 14, weight: .semibold))
                .tracking(2.0)
        case .labelSmall:
            return self
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
        case .labelTiny:
            return self
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
        case .meta:
            return self
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(0.7)
                .monospacedDigit()
        case .bodyText:
            return self
                .font(.system(size: 13, weight: .medium))
        case .transcript:
            return self
                .font(.system(size: 16))
        case .nineLineValue:
            return self
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .tracking(0.3)
                .monospacedDigit()
        case .bigVital:
            return self
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .tracking(-0.8)
                .monospacedDigit()
        case .smallVital:
            return self
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .monospacedDigit()
        case .h1:
            return self
                .font(.system(size: 26, weight: .bold))
                .tracking(0.5)
        case .timer:
            return self
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
    }
}
