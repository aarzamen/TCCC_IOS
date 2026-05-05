// RubricDriftProtectionTests
//
// Per 2026 sprint post-sprint audit: confirm at least one test
// references each ground-truth JSON in
// reference/rubric/extracted/ so the JSONs cannot silently drift out
// of sync with the code that binds to them.
//
// These tests parse each JSON and assert on canonical anchors
// extracted during the sprint. If someone deletes / renames /
// corrupts a JSON, or changes a load-bearing top-level field, the
// test fires immediately.

import XCTest

final class RubricDriftProtectionTests: XCTestCase {

    /// Repo root, resolved relative to this test file's location:
    ///   Packages/TCCCKit/Tests/TCCCExtractorTests/RubricDriftProtectionTests.swift
    /// First deletingLastPathComponent strips the file name; the next four
    /// strip Tests/TCCCExtractorTests, Tests, TCCCKit, Packages — leaving
    /// the repo root.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // -> TCCCExtractorTests/
            .deletingLastPathComponent()  // -> Tests/
            .deletingLastPathComponent()  // -> TCCCKit/
            .deletingLastPathComponent()  // -> Packages/
            .deletingLastPathComponent()  // -> repo root
    }

    private func jsonURL(_ filename: String) -> URL {
        repoRoot
            .appendingPathComponent("reference")
            .appendingPathComponent("rubric")
            .appendingPathComponent("extracted")
            .appendingPathComponent(filename)
    }

    private func loadJSON(_ filename: String) throws -> [String: Any] {
        let data = try Data(contentsOf: jsonURL(filename))
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = raw as? [String: Any] else {
            XCTFail("\(filename) did not parse as a top-level dictionary")
            throw CocoaError(.coderInvalidValue)
        }
        return dict
    }

    // MARK: - DD 1380 field inventory

    func testDD1380FieldInventoryExists() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: jsonURL("dd1380_field_inventory.json").path),
            "Sprint ground-truth JSON missing: dd1380_field_inventory.json")
    }

    func testDD1380HasMOIField() throws {
        let json = try loadJSON("dd1380_field_inventory.json")
        let fields = json["fields"] as? [[String: Any]]
        XCTAssertNotNil(fields, "DD 1380 inventory missing top-level 'fields' array")
        let moi = fields?.first { ($0["field_label"] as? String) == "Mechanism of Injury:" }
        XCTAssertNotNil(moi, "DD 1380 §B Mechanism of Injury field absent")
    }

    func testDD1380AVPUEnumIntact() throws {
        let json = try loadJSON("dd1380_field_inventory.json")
        let fields = json["fields"] as? [[String: Any]] ?? []
        let avpu = fields.first { ($0["field_label"] as? String) == "AVPU" }
        let allowed = avpu?["allowed_values"] as? [String]
        XCTAssertEqual(allowed, ["A", "V", "P", "U"],
                       "AVPU allowed values drifted from canonical A/V/P/U")
    }

    // MARK: - MARCH-PAWS canonical vocabulary

    func testMARCHPAWSVocabularyExists() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: jsonURL("march_paws_vocabulary_2026.json").path),
            "Sprint ground-truth JSON missing: march_paws_vocabulary_2026.json")
    }

    func testMARCHHasAllFivePhases() throws {
        let json = try loadJSON("march_paws_vocabulary_2026.json")
        let march = json["MARCH"] as? [String: Any]
        XCTAssertNotNil(march?["M"])
        XCTAssertNotNil(march?["A"])
        XCTAssertNotNil(march?["R"])
        XCTAssertNotNil(march?["C"])
        XCTAssertNotNil(march?["H_hypothermia"])
        XCTAssertNotNil(march?["H_tbi"])
    }

    func testTBIBPTargetIsGreaterThan100() throws {
        // 2026 §8 changed the TBI SBP target from 100-110 to >100.
        // This test pins that change so a regression in the JSON would fire.
        let json = try loadJSON("march_paws_vocabulary_2026.json")
        let march = json["MARCH"] as? [String: Any] ?? [:]
        let hTbi = march["H_tbi"] as? [String: Any] ?? [:]
        let thresholds = hTbi["decision_thresholds"] as? [[String: Any]] ?? []
        let sbp = thresholds.first { ($0["criterion"] as? String) == "TBI SBP target" }
        let value = sbp?["threshold"] as? String
        XCTAssertEqual(value, "> 100 mmHg",
                       "2026 §8 TBI SBP target drifted from '> 100 mmHg'")
    }

    func testSection19DocumentationMandatePresent() throws {
        // The §19 verbatim mandate is the load-bearing protocol anchor
        // that ties the entire app to DD 1380 as the deliverable.
        let json = try loadJSON("march_paws_vocabulary_2026.json")
        let mandate = json["documentation_mandate"] as? [String: Any]
        let verbatim = mandate?["verbatim"] as? String
        XCTAssertNotNil(verbatim)
        XCTAssertTrue(verbatim?.contains("DD Form 1380") ?? false,
                      "§19 documentation mandate must name DD Form 1380")
        XCTAssertTrue(verbatim?.contains("Forward documentation") ?? false,
                      "§19 verbatim must include 'Forward documentation' clause")
    }
}
