import SwiftUI

enum Layout {
    static let statusStripHeight: CGFloat = 36
    static let dynamicIslandClearance: CGFloat = 56
    static let pageHeaderHeight: CGFloat = 54
    static let footerHintsHeight: CGFloat = 30
    static let homeIndicatorClearance: CGFloat = 36

    static let panelPadding: CGFloat = 12
    static let outerPadding: CGFloat = 8
    static let gridGap: CGFloat = 8

    static let cornerRadiusSmall: CGFloat = 2
    static let cornerRadiusMedium: CGFloat = 4
    static let cornerRadiusLarge: CGFloat = 6

    static let hairline: CGFloat = 1
    static let bracketSize: CGFloat = 12

    static let minHitTarget: CGFloat = 44
    static let bigButtonHeight: CGFloat = 48
    static let swipeThreshold: CGFloat = 50

    static let fastDuration: Double = 0.12
    static let standardDuration: Double = 0.22
    static let pageTransitionDuration: Double = 0.32
}

extension Animation {
    static var pageTransition: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: Layout.pageTransitionDuration)
    }
    static var standard: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: Layout.standardDuration)
    }
    static var fast: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: Layout.fastDuration)
    }
}
