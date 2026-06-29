import XCTest
import TCCCDomain
import TCCCReports
@testable import TCCC_IOS

/// Part C: the §C grid used for DD1380 export must survive encounter recovery,
/// not depend on ephemeral UI state. Exercises SectionCReading Codable +
/// EncounterStore save/load across a fresh store instance (relaunch sim) +
/// the toDD1380() conversion.
final class SectionCPersistenceTests: XCTestCase {

    private func makeReading() -> AppState.SectionCReading {
        AppState.SectionCReading(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            vitals: Vitals(hr: 96, bp: BloodPressure(systolic: 120, diastolic: 80), spo2: 97, rr: 18),
            avpu: "Alert"
        )
    }

    func testSectionCSurvivesEncounterStoreRoundTrip() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tccc-sc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = EncounterStore(baseURL: tmp)
        try await store.startNewCasualty(id: "C-TEST", startUnix: 1_700_000_000)

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        try await store.saveSectionC(try enc.encode([makeReading()]))

        // Fresh store instance pointed at the same baseURL = simulated relaunch.
        let store2 = EncounterStore(baseURL: tmp)
        _ = try await store2.loadActiveEncounter()    // resolves + sets activeDir
        let loaded = await store2.loadSectionC()
        let data = try XCTUnwrap(loaded, "§C grid must persist across recovery")

        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        let restored = try dec.decode([AppState.SectionCReading].self, from: data)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.vitals.hr, 96)
        XCTAssertEqual(restored.first?.avpu, "Alert")

        // Conversion into the DD1380 grid column.
        let column = try XCTUnwrap(restored.first?.toDD1380())
        XCTAssertEqual(column.pulse, "96")
        XCTAssertEqual(column.bloodPressure, "120/80")
        XCTAssertEqual(column.respiratoryRate, "18")
        XCTAssertEqual(column.spo2, "97")
        XCTAssertEqual(column.avpu, "A")          // "Alert" → A
        XCTAssertNil(column.pain)                  // no pain source in Vitals
    }

    func testLoadSectionCNilWhenNonePersisted() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tccc-sc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = EncounterStore(baseURL: tmp)
        try await store.startNewCasualty(id: "C-TEST", startUnix: 1_700_000_000)
        let none = await store.loadSectionC()
        XCTAssertNil(none, "No §C file yet → nil, not a crash.")
    }
}
