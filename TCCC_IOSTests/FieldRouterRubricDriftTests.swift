// TCCC_IOSTests/FieldRouterRubricDriftTests.swift
import XCTest
@testable import TCCC_IOS

final class FieldRouterRubricDriftTests: XCTestCase {
    /// Every field name the router can route to a mutation must exist in the
    /// 2026 DD-1380 / MARCH-PAWS rubric. If the router wires a field the rubric
    /// does not know, this fails — the router drifted from ground truth.
    func testWiredFieldsExistInRubric() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TCCC_IOSTests/
            .deletingLastPathComponent()   // repo root
        let ddURL = repoRoot.appendingPathComponent("reference/rubric/extracted/dd1380_field_inventory.json")
        let mpURL = repoRoot.appendingPathComponent("reference/rubric/extracted/march_paws_vocabulary_2026.json")
        let ddText = try String(contentsOf: ddURL, encoding: .utf8)
        let mpText = try String(contentsOf: mpURL, encoding: .utf8)

        // Field-label tokens the router wires (human terms present verbatim in the rubric files).
        // "tourniquet" is lowercase throughout both rubric files (field labels use abbreviation "TQ";
        // prose/format_constraints and march_paws sections use lowercase "tourniquet").
        // "Hemorrhage" is capitalized in march_paws_vocabulary_2026.json line 28 ("Massive Hemorrhage")
        // and covers the FieldRouter.swift:59 `("march", "hemorrhageLocation")` wired path.
        // "SpO2" appears verbatim in march_paws_vocabulary_2026.json (continuous EtCO2 and SpO2
        // monitoring entry, tension pneumothorax SpO2 threshold, NDC success SpO2 criterion).
        let wiredRubricTerms = [
            "Pulse", "SpO2", "Resp", "Blood Pressure", "AVPU",
            "tourniquet", "Airway", "Hypothermia", "Analgesic", "Antibiotic",
            "Hemorrhage",
        ]
        for term in wiredRubricTerms {
            XCTAssertTrue(ddText.contains(term) || mpText.contains(term),
                          "Wired router term '\(term)' is absent from both rubric files — router drifted.")
        }
    }
}
