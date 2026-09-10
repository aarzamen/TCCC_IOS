import XCTest
@testable import TCCCDesignSystem

final class DataViewTests: XCTestCase {
    private func sample(_ id: String, _ time: Double, _ value: Double?) -> VitalSample {
        VitalSample(id: id, timestamp: Date(timeIntervalSince1970: time), value: value)
    }

    func testTrendEmptySingletonTimeSpacingAndUnknownGaps() {
        XCTAssertTrue(TrendPlot(samples: [], band: nil).segments.isEmpty)
        let singleton = TrendPlot(samples: [sample("a", 0, 10)], band: nil)
        XCTAssertEqual(singleton.segments[0][0].x, 0.5)
        XCTAssertEqual(singleton.segments[0][0].y, 0.5)
        let plot = TrendPlot(samples: [sample("d", 100, 30), sample("a", 0, 10),
                                     sample("b", 10, 20), sample("c", 50, nil)], band: nil)
        XCTAssertEqual(plot.segments.map(\.count), [2, 1])
        XCTAssertEqual(plot.segments[0][1].x, 0.1, accuracy: 0.00001)
        XCTAssertEqual(plot.segments[1][0].x, 1)
        XCTAssertNil(plot.latestValue(from: [sample("a", 0, 10), sample("b", 1, nil)]))
    }

    func testTrendFiniteExtremesAndInvalidInputsNeverCreateInvalidGeometry() {
        let extreme = Double.greatestFiniteMagnitude
        let plot = TrendPlot(samples: [sample("a", -extreme, -extreme), sample("b", 0, .nan),
                                     sample("c", extreme, extreme), sample("d", .infinity, 12)],
                             band: VitalReferenceBand(lower: -.infinity, upper: 1, label: "Invalid"))
        XCTAssertNil(plot.bandRange)
        XCTAssertEqual(plot.segments.map(\.count), [1, 1])
        for point in plot.segments.flatMap({ $0 }) {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
        }
        XCTAssertNil(VitalReferenceBand(lower: 10, upper: 1, label: "Reversed").validRange)
        XCTAssertEqual(DataDisplay.date(Date(timeIntervalSince1970: .nan), timeZone: .gmt), "Unknown time")
    }

    func testTrendEqualTimestampsUseLastSuppliedObservationForPlotAndLatestValue() {
        let changed = [sample("a", 20, 10), sample("b", 20, 99)]
        let plot = TrendPlot(samples: changed, band: nil)
        XCTAssertEqual(plot.ordered.last?.id, "b")
        XCTAssertEqual(plot.latestValue(from: changed), 99)
        XCTAssertNil(plot.latestValue(from: [sample("a", 20, 10), sample("b", 20, nil)]))
    }

    func testTimelinePreservesStableSelectionAndRemovesStaleDetail() {
        let a = TimelineEvent(id: "a", timestamp: .distantPast, title: "First")
        let b = TimelineEvent(id: "b", timestamp: .distantPast, title: "Second")
        XCTAssertEqual(TimelineSelection.events([a, a, b]).map(\.id), ["a", "b"])
        XCTAssertEqual(TimelineSelection.selectedID("b", in: [b, a]), "b")
        XCTAssertEqual(TimelineSelection.selectedID("b", in: [a]), "a")
        XCTAssertNil(TimelineSelection.selectedID("b", in: []))
    }

    func testBodyLateralityAndActualButtonGeometryAtAllTargetSizes() {
        for glove in [false, true] {
            for scale in [1.0, 2.0, 3.1] {
                let metrics = ThemeMetrics(gloveMode: glove, scale: scale)
                let geometry = BodyGeometry(tap: metrics.tap)
                for side in BodySide.allCases {
                    let rectangles = BodyRegion.allCases.map { geometry.rect(for: $0, side: side) }
                    XCTAssertEqual(rectangles.count, 7)
                    for (index, rect) in rectangles.enumerated() {
                        XCTAssertGreaterThanOrEqual(rect.width, metrics.tap)
                        XCTAssertGreaterThanOrEqual(rect.height, metrics.tap)
                        for other in rectangles.dropFirst(index + 1) { XCTAssertFalse(rect.intersects(other)) }
                    }
                    let right = geometry.rect(for: .rightArm, side: side)
                    let left = geometry.rect(for: .leftArm, side: side)
                    XCTAssertEqual(right.midX < left.midX, side == .anterior)
                    XCTAssertEqual(geometry.rect(for: .rightLeg, side: side).midX < geometry.rect(for: .leftLeg, side: side).midX, side == .anterior)
                }
            }
        }
    }

    func testScriptResetsOnSameCountContentChangeAndSourceChange() {
        let original = [RadioScriptLine(id: "a", label: "One", text: "First"), RadioScriptLine(id: "b", label: "Two", text: "Second")]
        var selection = ScriptSelection()
        selection.select(1, sourceID: "source", lines: original)
        XCTAssertEqual(selection.index(sourceID: "source", lines: original), 1)
        XCTAssertEqual(selection.index(sourceID: "changed", lines: original), 0)
        XCTAssertEqual(selection.index(sourceID: "source", lines: [original[0], RadioScriptLine(id: "b", label: "Two", text: "Edited")]), 0)
        XCTAssertNil(selection.index(sourceID: "source", lines: []))
    }

    func testExportReadinessAndConfidenceRemainIndependent() {
        XCTAssertTrue(ExportReadiness.ready.canAct(hasAction: true))
        XCTAssertFalse(ExportReadiness.ready.canAct(hasAction: false))
        XCTAssertFalse(ExportReadiness.pending("Building").canAct(hasAction: true))
        XCTAssertFalse(ExportReadiness.unavailable("Absent").canAct(hasAction: true))
        XCTAssertEqual(ConfidenceDisplay.text(0.99), "99%")
        for value in [Double.nan, .infinity, -0.1, 1.1] { XCTAssertEqual(ConfidenceDisplay.text(value), "Unknown") }
        XCTAssertEqual(HumanVerification.unreviewed.title, "Human verification: Not reviewed")
    }
}
