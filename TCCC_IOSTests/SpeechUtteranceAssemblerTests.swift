import XCTest
@testable import TCCC_IOS

final class SpeechUtteranceAssemblerTests: XCTestCase {

    /// Metadata windows observed on a physical device for a single URL request
    /// that delivered 763 callbacks (metadata-bearing callbacks 87, 181, 312,
    /// 392, 487, 596, 688, 761 — all with isFinal=false).
    private static let deviceWindows: [(start: TimeInterval, duration: TimeInterval)] = [
        (7.83, 26.73), (34.56, 22.53), (58.38, 32.07), (91.44, 23.64),
        (116.16, 23.85), (141.18, 29.28), (171.6, 23.82), (196.8, 22.35),
    ]

    // MARK: Observed device pattern — boundary resets, then empty final

    func testShortNewUtteranceIsNotMistakenForPreviousWindowEcho() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "pulse checked", speechStart: 1, speechDuration: 3)
        assembler.ingest(text: "no")
        assembler.ingest(text: "no", speechStart: 4, speechDuration: 0.2)
        assembler.ingest(text: "airway")
        XCTAssertEqual(assembler.transcript, "pulse checked no airway")
        assembler.ingest(text: "airway", speechStart: 4.2, speechDuration: 1)
        XCTAssertEqual(assembler.transcript, "pulse checked no airway")
    }

    func testMetadataBoundaryResetsRetainEveryUtterance() {
        var assembler = SpeechUtteranceAssembler()
        var expected: [String] = []
        for (index, window) in Self.deviceWindows.enumerated() {
            let full = "utterance \(index) alpha bravo charlie"
            expected.append(full)
            // Volatile partials build with zero segment times and nil metadata.
            assembler.ingest(text: "utterance", segmentStart: 0, segmentEnd: 0)
            assembler.ingest(text: "utterance \(index) alpha", segmentStart: 0, segmentEnd: 0)
            // Metadata-bearing callback carries the full utterance and a valid window.
            assembler.ingest(
                text: full,
                speechStart: window.start,
                speechDuration: window.duration,
                segmentStart: window.start,
                segmentEnd: window.start + window.duration
            )
            // The next callback resets to one word (start of the next utterance);
            // that happens at the top of the next loop iteration.
        }
        // Callback 762: isFinal=true with empty text and nil metadata.
        assembler.ingest(text: "")
        XCTAssertEqual(assembler.transcript, expected.joined(separator: " "),
                       "Every metadata-finalized utterance must survive the reset that follows it")
    }

    func testSingleBoundaryResetDoesNotLoseEarlierUtterance() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "massive hemorrhage controlled with tourniquet",
                         speechStart: 7.83, speechDuration: 26.73)
        // Reset: recognizer starts the next utterance from one word.
        assembler.ingest(text: "airway")
        XCTAssertEqual(assembler.transcript,
                       "massive hemorrhage controlled with tourniquet airway",
                       "The reset partial must append after the timed utterance, not overwrite it")
    }

    // MARK: Volatile revision within one utterance

    func testUntimedRevisionsReplaceWithinCurrentUtterance() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "the")
        assembler.ingest(text: "the patient")
        assembler.ingest(text: "the casualty has a chest seal")
        XCTAssertEqual(assembler.transcript, "the casualty has a chest seal")
    }

    func testUntimedRevisionsAfterBoundaryReplaceOnlyActiveUtterance() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "first utterance complete", speechStart: 1.0, speechDuration: 3.0)
        assembler.ingest(text: "second")
        assembler.ingest(text: "second thought revised")
        XCTAssertEqual(assembler.transcript, "first utterance complete second thought revised")
    }

    // MARK: Genuine repeated utterances

    func testRepeatedIdenticalUtterancesAtDifferentTimesAreRetained() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "check airway")
        assembler.ingest(text: "check airway", speechStart: 5.0, speechDuration: 2.0)
        assembler.ingest(text: "check")
        assembler.ingest(text: "check airway")
        assembler.ingest(text: "check airway", speechStart: 12.0, speechDuration: 2.0)
        XCTAssertEqual(assembler.transcript, "check airway check airway",
                       "Identical text in distinct timing windows is two real utterances")
    }

    // MARK: Duplicate/echoed metadata

    func testDuplicateTimedCallbackDoesNotDuplicateOrClearActivePartial() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "apply pressure dressing now", speechStart: 3.0, speechDuration: 4.0)
        assembler.ingest(text: "start")
        // Same window and text delivered again.
        assembler.ingest(text: "apply pressure dressing now", speechStart: 3.0, speechDuration: 4.0)
        assembler.ingest(text: "start second line")
        XCTAssertEqual(assembler.transcript, "apply pressure dressing now start second line")
    }

    func testLateTimedEchoDoesNotAppendStaleTextOrEraseActivePartial() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "first utterance words", speechStart: 2.0, speechDuration: 3.0)
        assembler.ingest(text: "second utterance words", speechStart: 6.0, speechDuration: 3.0)
        assembler.ingest(text: "third partial")
        // Echo entirely at/before the last finalized window, with stale truncated text
        // whose window matches no finalized utterance cleanly.
        assembler.ingest(text: "first utterance", speechStart: 2.0, speechDuration: 2.1)
        XCTAssertEqual(assembler.transcript,
                       "first utterance words second utterance words third partial")
    }

    // MARK: Timed corrections

    func testTimedCorrectionForSameUtteranceReplacesIt() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "apply turn a kit high and tight", speechStart: 3.0, speechDuration: 4.0)
        assembler.ingest(text: "next")
        // Correction for the same window arrives after the next utterance started.
        assembler.ingest(text: "apply tourniquet high and tight", speechStart: 3.0, speechDuration: 4.0)
        XCTAssertEqual(assembler.transcript, "apply tourniquet high and tight next")
    }

    func testCumulativeTimedCorrectionReplacesCoveredUtterancesWithoutDuplication() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "alpha one", speechStart: 1.0, speechDuration: 2.0)
        assembler.ingest(text: "bravo two", speechStart: 4.0, speechDuration: 2.0)
        assembler.ingest(text: "charlie")
        // Cumulative window spans both finalized utterances plus the active speech.
        assembler.ingest(text: "alpha one bravo two charlie three",
                         speechStart: 1.0, speechDuration: 8.0)
        XCTAssertEqual(assembler.transcript, "alpha one bravo two charlie three")
    }

    // MARK: Empty, nil and invalid input

    func testNilAndEmptyCallbacksPreserveEvidence() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "hold pressure", speechStart: 1.0, speechDuration: 2.0)
        assembler.ingest(text: "then")
        assembler.ingest(text: nil)
        assembler.ingest(text: "")
        assembler.ingest(text: "   ")
        assembler.ingest(text: nil, speechStart: 5.0, speechDuration: 2.0)
        XCTAssertEqual(assembler.transcript, "hold pressure then")
    }

    func testInvalidTimingIsSafelyTreatedAsVolatilePartial() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "stable words", speechStart: 1.0, speechDuration: 2.0)
        assembler.ingest(text: "next", speechStart: .nan, speechDuration: .infinity)
        assembler.ingest(text: "next words", speechStart: 5.0, speechDuration: 0)
        assembler.ingest(text: "next words go", speechStart: -3.0, speechDuration: -1.0)
        XCTAssertEqual(assembler.transcript, "stable words next words go",
                       "Nonfinite or non-positive-duration timing must not finalize a boundary")
    }

    func testZeroSegmentTimesAreNotTreatedAsStaleEvidence() {
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "word", segmentStart: 0, segmentEnd: 0)
        assembler.ingest(text: "word two", segmentStart: 0, segmentEnd: 0)
        XCTAssertEqual(assembler.transcript, "word two")
    }

    func testEmptyAssemblerHasEmptyTranscript() {
        let assembler = SpeechUtteranceAssembler()
        XCTAssertEqual(assembler.transcript, "")
    }
}
