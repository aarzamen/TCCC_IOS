import Foundation
import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class GraniteCaptureEvidenceTests: XCTestCase {
    func testFailedAndCancelledTextPersistsForReviewWithoutClinicalVitals() async throws {
        for termination in [CaptureTermination.failed, .cancelled] {
            let state = AppState()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            state.documentsURL = directory
            state.encounterStore = EncounterStore(baseURL: directory)
            let store = try XCTUnwrap(state.encounterStore)
            try await store.startNewCasualty(id: state.casualtyId,
                startUnix: Date().timeIntervalSince1970)
            let generation = state.beginCapture(backend: .graniteSpeech)
            let request = UUID()
            let text = "heart rate 180 oxygen saturation 82"

            await state.receiveAppleCapture(RecognitionUpdate(text: text, isFinal: false,
                timestamp: Date(), requestID: request), generation: generation)
            XCTAssertEqual(state.partialTranscript, text)
            await state.receiveAppleCapture(RecognitionUpdate(text: text, isFinal: false,
                timestamp: Date(), requestID: request, termination: termination), generation: generation)

            XCTAssertEqual(state.partialTranscript, "")
            XCTAssertTrue(state.transcript.contains {
                $0.text.contains("CAPTURE INCOMPLETE (\(termination.rawValue))") && $0.text.contains(text)
            })
            XCTAssertFalse(state.transcript.contains { $0.speaker == .medic })
            XCTAssertTrue(state.transcriptLedger.rawSegments.isEmpty)
            let snapshot = await state.engine.snapshot(of: "PATIENT_1")
            XCTAssertNil(snapshot?.vitals.hr)
            XCTAssertNil(snapshot?.vitals.spo2)

            let restored = try await store.loadActiveEncounter()
            let log = try XCTUnwrap(restored?.1)
            XCTAssertTrue(log.events.contains { event in
                if case .asrSegment(let segment) = event {
                    return !segment.isFinal && segment.text.contains(text)
                        && segment.text.contains("CAPTURE INCOMPLETE (\(termination.rawValue))")
                        && segment.backend == "graniteSpeech"
                }
                return false
            })
            let replay = PatientStateEngine.standard()
            await replay.restore(log)
            let replayed = await replay.snapshot(of: "PATIENT_1")
            XCTAssertNil(replayed?.vitals.hr)
            XCTAssertNil(replayed?.vitals.spo2)
        }
    }

    func testSuccessfulFinalKeepsGraniteProvenanceAfterNextBackendSelection() async throws {
        let state = AppState()
        let generation = state.beginCapture(backend: .graniteSpeech)
        // Selecting the next backend cannot relabel a result from this capture.
        state.asrBackend = .appleSpeech
        let text = "heart rate 110"
        await state.receiveAppleCapture(RecognitionUpdate(text: text, isFinal: true,
            timestamp: Date(), requestID: UUID(), termination: .finalized), generation: generation)

        XCTAssertEqual(state.primaryPatient?.vitals.hr, 110)
        XCTAssertEqual(state.transcript.filter { $0.speaker == .medic }.map(\.text), [text])
        let segment = try XCTUnwrap(state.transcriptLedger.rawSegments.last)
        XCTAssertEqual(segment.backend, .graniteSpeech)
        XCTAssertTrue(segment.isFinal)
        XCTAssertEqual(segment.textRaw, text)
        let log = await state.engine.snapshotLog()
        XCTAssertTrue(log.events.contains { event in
            if case .asrSegment(let segment) = event {
                return segment.isFinal && segment.text == text && segment.backend == "graniteSpeech"
            }
            return false
        })
    }

    func testEarlierGraniteAudioCannotOverwriteCorrectionBeforeFirstCallback() async {
        let state = AppState()
        let generation = state.beginCapture(backend: .graniteSpeech)
        let capturedAt = ProcessInfo.processInfo.systemUptime
        await state.engine.recordOperatorAcceptedFact(write: .heartRate(90), factId: nil,
            domain: "vitals", field: "hr", rawValue: "90", to: "PATIENT_1")

        // No partial callback preceded the correction, so the timestamp must
        // provide protection even though the request's operator revision is new.
        await state.receiveAppleCapture(RecognitionUpdate(text: "heart rate 180", isFinal: true,
            timestamp: Date(), requestID: UUID(), termination: .finalized,
            requestStartedAt: capturedAt), generation: generation)

        let patient = await state.engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 90)
        XCTAssertTrue(state.transcript.contains { $0.text.contains("REVIEW REQUIRED · heart rate 180") })
        XCTAssertFalse(state.transcript.contains { $0.speaker == .medic })
        XCTAssertTrue(state.transcriptLedger.rawSegments.isEmpty)
        let log = await state.engine.snapshotLog()
        XCTAssertTrue(log.events.contains { event in
            if case .asrSegment(let segment) = event {
                return !segment.isFinal && segment.text.contains("REVIEW REQUIRED · heart rate 180")
                    && segment.backend == "graniteSpeech"
            }
            return false
        })
    }
}
