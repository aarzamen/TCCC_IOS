import XCTest
@testable import TCCCDesignSystem

final class ThemeTests: XCTestCase {
    func testReferencePalettesRetainEveryExactRGBToken() {
        let base: [UInt32] = [0x0B0D10, 0x141820, 0x1B2029, 0x2A303A, 0xE6E8EB, 0x8A93A0, 0x5B6470, 0x59C3E8, 0x4CC38A, 0xE8B44C, 0xE5484D]
        let night: [UInt32] = [0x070404, 0x120909, 0x1A0C0C, 0x3A1A1A, 0xE0A070, 0x9A6A4A, 0x5A3A2A, 0xD89A6A, 0xC88A50, 0xE0A050, 0xFF4A3A]
        for (theme, expected) in [(Theme.base, base), (Theme.night, night)] {
            let p = theme.palette
            let actual = [p.background, p.panel, p.panel2, p.line, p.ink, p.muted, p.dim, p.ai, p.ok, p.warn, p.danger]
            XCTAssertEqual(actual, expected.map { ThemeColor(hex: $0) })
        }
    }

    func testAccentsPreserveReferenceHSLAndNightRGB() {
        let accent = Theme.base.palette.accent
        XCTAssertEqual(accent.red, 0.9472, accuracy: 0.0000001)
        XCTAssertEqual(accent.green, 0.52128, accuracy: 0.0000001)
        XCTAssertEqual(accent.blue, 0.1728, accuracy: 0.0000001)
        XCTAssertEqual(Theme.night.palette.accent, ThemeColor(hex: 0xFF5A3A))
    }

    func testEveryButtonSizeKeepsTouchMinimumAndScalesUp() {
        for glove in [false, true] {
            for size in ActionButtonSize.allCases {
                for scale in [0.5, 1, 1.4, 2, 3] {
                    let metrics = ThemeMetrics(gloveMode: glove, scale: scale)
                    XCTAssertGreaterThanOrEqual(metrics.buttonHeight(size), glove ? 60 : 44)
                    XCTAssertGreaterThanOrEqual(metrics.tap, glove ? 60 : 44)
                    XCTAssertGreaterThanOrEqual(metrics.row, glove ? 64 : 52)
                }
                XCTAssertGreaterThan(ThemeMetrics(scale: 2).buttonHeight(size), ThemeMetrics().buttonHeight(size))
            }
        }
        XCTAssertEqual(ThemeMetrics().tap, 44)
        XCTAssertEqual(ThemeMetrics().row, 52)
        XCTAssertEqual(ThemeMetrics(gloveMode: true).tap, 60)
        XCTAssertEqual(ThemeMetrics(gloveMode: true).row, 64)
    }

    func testInvalidScaleCannotCreateUnusableGeometry() {
        for scale in [Double.nan, Double.infinity, -Double.infinity, -1, 0] {
            let metrics = ThemeMetrics(scale: scale)
            XCTAssertEqual(metrics.tap, 44)
            XCTAssertEqual(metrics.row, 52)
        }
    }
}
