import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class HandoffCSVTests: XCTestCase {
    func testAudioShareIncludesOnlyExplicitCurrentArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("current.m4a")
        let diagnosticsDirectory = try FileManager.default.url(for: .documentDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let diagnostic = diagnosticsDirectory.appendingPathComponent("diagnostics-synthetic-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: diagnostic) }
        try Data("synthetic audio".utf8).write(to: audio)
        try Data("prior diagnostic session".utf8).write(to: diagnostic)
        let line = TranscriptLine(speaker: .medic, text: "current synthetic evidence", timestamp: Date())
        let items = try HandoffAudioExport.items(audioURL: audio, transcript: [line], casualtyId: UUID().uuidString)
        defer { for url in items where url != audio { try? FileManager.default.removeItem(at: url) } }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first, audio)
        XCTAssertFalse(items.contains(diagnostic))
        XCTAssertTrue(try String(contentsOf: items[1], encoding: .utf8).contains(line.text))
    }

    func testMissingAudioAndEmptyTranscriptCannotShareOnlyDiagnostics() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try HandoffAudioExport.items(audioURL: missing, transcript: [], casualtyId: "TEST"))
    }

    func testCSVUsesRecordedTimesInChronologicalOrderAndRetainsAVPU() {
        let early = AppState.SectionCReading(
            timestamp: Date(timeIntervalSince1970: 0), vitals: Vitals(hr: 110), avpu: "Alert")
        let late = AppState.SectionCReading(
            timestamp: Date(timeIntervalSince1970: 60), vitals: Vitals(rr: 20), avpu: "Voice")
        let csv = HandoffExports.vitalsCSV(readings: [late, early])
        let rows = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], "timestamp,hr,sys,dia,bp_palpated,spo2,rr,gcs,temperature_c,capillary_refill_seconds,avpu,pain")
        XCTAssertEqual(rows[1], "1970-01-01T00:00:00Z,110,,,,,,,,,Alert,")
        XCTAssertEqual(rows[2], "1970-01-01T00:01:00Z,,,,,,20,,,,Voice,")
    }

    func testEmptyHistoryDoesNotInventAnExportTimeObservation() {
        let csv = HandoffExports.vitalsCSV(readings: [])
        XCTAssertEqual(csv.split(separator: "\n").count, 1)
    }

    func testCSVPreservesUnknownsAndEscapesSourceText() {
        let reading = AppState.SectionCReading(
            timestamp: Date(timeIntervalSince1970: 0),
            vitals: Vitals(gcs: 12, temperatureCelsius: 36.5, capillaryRefillSeconds: 2),
            avpu: "Voice, \"recorded\"")
        let csv = HandoffExports.vitalsCSV(readings: [reading])
        XCTAssertTrue(csv.contains(",12,36.5,2.0,\"Voice, \"\"recorded\"\"\",\n"))
        XCTAssertFalse(csv.contains("NKDA"))
    }

    func testPriorityDoesNotInferTransportModeOrMedevacRequest() {
        var patient = PatientState(patientId: "TEST")
        patient.classification = .urgent
        let line = HandoffSummary.lines(for: patient, casualtyId: "TEST").first { $0.label == "PRIORITY" }
        XCTAssertEqual(line?.value, "URGENT")
    }

    func testCSVPreservesPerReadingPainAndLeavesUnknownPainBlank() {
        let early = AppState.SectionCReading(timestamp: Date(timeIntervalSince1970: 0),
            vitals: Vitals(), avpu: nil, pain: "7/10")
        let late = AppState.SectionCReading(timestamp: Date(timeIntervalSince1970: 60),
            vitals: Vitals(), avpu: nil)
        let rows = HandoffExports.vitalsCSV(readings: [early, late]).split(separator: "\n")
        XCTAssertTrue(rows[1].hasSuffix(",7/10"))
        XCTAssertTrue(rows[2].hasSuffix(","))
        XCTAssertFalse(rows[2].contains("7/10"))
    }

    func testTimelineUsesRecordedRadioTimeAndDoesNotInventCasualtyContact() throws {
        let start = Date(timeIntervalSince1970: 0)
        let radio = Date(timeIntervalSince1970: 60)
        let rows = HandoffTimeline.events(for: nil, sessionStart: start, medevacTransmittedAt: radio)
        XCTAssertEqual(rows.first?.detail, "Encounter started")
        XCTAssertFalse(rows.contains { $0.detail == "Casualty contact" })
        let event = try XCTUnwrap(rows.first { $0.kindLabel == "9L" })
        XCTAssertEqual(event.timestamp, radio)
        XCTAssertFalse(HandoffTimeline.events(for: nil, sessionStart: start).contains { $0.kindLabel == "9L" })
    }
}
