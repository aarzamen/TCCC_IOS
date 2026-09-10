import XCTest
@testable import TCCCDesignSystem

final class BehaviorTests: XCTestCase {
    func testHoldReleasePreventsDelayedCompletionAndRearmsOnlyNewContact() {
        var hold = HoldState()
        let first = hold.begin(at: 10)!
        XCTAssertEqual(hold.progress(at: 10.45, duration: 0.9), 0.5, accuracy: 0.001)
        hold.release()
        XCTAssertFalse(hold.complete(generation: first, isPressed: true))
        let second = hold.begin(at: 20)!
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(hold.complete(generation: second, isPressed: true))
        XCTAssertFalse(hold.complete(generation: second, isPressed: true))
        XCTAssertNil(hold.begin(at: 21), "A continuing physical hold must never rearm")
        hold.release()
        XCTAssertNotNil(hold.begin(at: 22))
    }

    func testCancellationLatchesUntilReleaseAndFencesStaleWork() {
        for _ in ["movement", "disabled", "inactive", "disappearance"] {
            var hold = HoldState()
            let generation = hold.begin(at: 0)!
            hold.cancel()
            XCTAssertEqual(hold.progress(at: 10, duration: 0.9), 0)
            XCTAssertFalse(hold.complete(generation: generation, isPressed: true))
            XCTAssertNil(hold.begin(at: 10))
            hold.release()
            let next = hold.begin(at: 11)!
            XCTAssertFalse(hold.complete(generation: generation, isPressed: true))
            XCTAssertFalse(hold.complete(generation: next, isPressed: false))
        }
    }

    func testElapsedUnknownFutureAndOver24Hours() {
        let now = Date(timeIntervalSince1970: 200_000)
        XCTAssertEqual(StatusTime.elapsed(startedAt: nil, now: now), "Unknown")
        XCTAssertEqual(StatusTime.elapsed(startedAt: now.addingTimeInterval(20), now: now), "00:00:00")
        XCTAssertEqual(StatusTime.elapsed(startedAt: now.addingTimeInterval(-90_061.9), now: now), "25:01:01")
        XCTAssertEqual(StatusTime.elapsed(startedAt: Date(timeIntervalSince1970: .nan), now: now), "Unknown")
    }

    func testTimeZoneIsExplicitAndZuluUsesUTC() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(StatusTime.zulu(date), "00:00:00Z")
        XCTAssertTrue(StatusTime.local(date, timeZone: TimeZone(secondsFromGMT: 3600)!).contains("01:00:00"))
        XCTAssertTrue(StatusTime.local(date, timeZone: TimeZone(secondsFromGMT: 3600)!).contains("GMT+0100"))
    }

    func testScrollEdgesTrackTopMiddleEndFitAndContentGrowth() {
        XCTAssertEqual(ScrollEdges(offset: 0, contentHeight: 500, viewportHeight: 200), .init(top: false, bottom: true))
        XCTAssertEqual(ScrollEdges(offset: 100, contentHeight: 500, viewportHeight: 200), .init(top: true, bottom: true))
        XCTAssertEqual(ScrollEdges(offset: 300, contentHeight: 500, viewportHeight: 200), .init(top: true, bottom: false))
        XCTAssertEqual(ScrollEdges(offset: 0, contentHeight: 200, viewportHeight: 200), .init(top: false, bottom: false))
        XCTAssertEqual(ScrollEdges(offset: 0, contentHeight: 350, viewportHeight: 200), .init(top: false, bottom: true))
        XCTAssertEqual(ScrollEdges(offset: -30, contentHeight: 100, viewportHeight: 200), .init(top: false, bottom: false))
        XCTAssertEqual(ScrollEdges(offset: .nan, contentHeight: 500, viewportHeight: 200), .init(top: false, bottom: false))
    }

    func testScrollViewportPreservesGloveTargetsAndScalesWithText() {
        XCTAssertEqual(ScrollViewport.height(requested: 44, metrics: ThemeMetrics(gloveMode: true)), 60)
        XCTAssertEqual(ScrollViewport.height(requested: 44, metrics: ThemeMetrics(gloveMode: true, scale: 2)), 120)
        XCTAssertEqual(ScrollViewport.height(requested: 200, metrics: ThemeMetrics(scale: 2)), 400)
        XCTAssertEqual(ScrollViewport.height(requested: .nan, metrics: ThemeMetrics()), 200)
        XCTAssertEqual(ScrollViewport.height(requested: -10, metrics: ThemeMetrics()), 44)
    }

    func testAssessmentCyclesIndependently() {
        var first = AssessmentState.none
        let second = AssessmentState.clear
        first = first.next
        XCTAssertEqual(first, .clear)
        first = first.next
        XCTAssertEqual(first, .done)
        first = first.next
        XCTAssertEqual(first, .none)
        XCTAssertEqual(second, .clear)
    }
}
