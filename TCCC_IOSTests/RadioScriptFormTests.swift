import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class RadioScriptFormTests: XCTestCase {
    private func form() -> NineLineForm {
        NineLineForm.derive(from: [], locationFix: .init(source: .none, latitude: nil, longitude: nil),
            operatorValues: [3: "2 PRIORITY", 4: "HOIST", 5: "2 LITTER", 8: "UNKNOWN"])
    }

    func testExactWorksheetRetainsOperatorValuesAndUnknowns() {
        let source = form()
        XCTAssertTrue(RadioScriptGenerator.preservesForm(RadioScriptGenerator.worksheet(source), form: source))
        XCTAssertTrue(RadioScriptGenerator.worksheet(source).contains("Line 4: HOIST"))
        XCTAssertTrue(RadioScriptGenerator.worksheet(source).contains("Line 1: UNVERIFIED"))
    }

    func testEveryFieldChangeIsRejectedIncludingOperationalLines() {
        let source = form()
        for entry in source.entries {
            let exact = RadioScriptGenerator.worksheet(source)
            let changed = exact.replacingOccurrences(of: "Line \(entry.number): \(entry.value)",
                with: "Line \(entry.number): fabricated replacement")
            XCTAssertFalse(RadioScriptGenerator.preservesForm(changed, form: source), "Line \(entry.number)")
        }
    }

    func testExtraMissingAndDuplicateLinesAreRejected() {
        let source = form()
        let exact = RadioScriptGenerator.worksheet(source)
        XCTAssertFalse(RadioScriptGenerator.preservesForm(exact + "\nPatient is stable.", form: source))
        XCTAssertFalse(RadioScriptGenerator.preservesForm(exact + "\nLine 9: NONE", form: source))
        XCTAssertFalse(RadioScriptGenerator.preservesForm(exact.components(separatedBy: "\n").dropLast().joined(separator: "\n"), form: source))
    }

    func testUnsafeOutputWithEmptyPatientsStillFallsBackToExactForm() async throws {
        let source = form()
        let output = try await RadioScriptGenerator(backend: RadioFormStub(text: "Line 4: NONE")).generate(from: source)
        XCTAssertEqual(output, RadioScriptGenerator.fallback(source))
        XCTAssertTrue(output.contains("Line 4: HOIST"))
        XCTAssertTrue(output.contains("Line 6: —"))
        XCTAssertTrue(output.contains("Line 8: UNKNOWN"))
        XCTAssertFalse(output.contains("US MIL"))
    }

    func testPatientInferenceCannotOverwriteManualValues() async throws {
        let source = form()
        let exact = RadioScriptGenerator.worksheet(source)
        let output = try await RadioScriptGenerator(backend: RadioFormStub(text: exact)).generate(
            from: source, patients: [PatientState(patientId: "PATIENT_1", classification: .urgent)],
            transcript: "synthetic unrelated earlier assessment")
        XCTAssertTrue(output.hasPrefix("LLM DRAFT"))
        XCTAssertTrue(output.contains("Line 3: 2 PRIORITY"))
        XCTAssertTrue(output.contains("Line 4: HOIST"))
        XCTAssertTrue(output.contains("Line 5: 2 LITTER"))
    }

    func testOnlyExactSuppliedOpeningIsAccepted() {
        let source = form()
        let opening = "ALPHA, ALPHA, this is BRAVO. Send MEDEVAC, over."
        let text = opening + "\n" + RadioScriptGenerator.worksheet(source) + "\nHow copy, over."
        XCTAssertTrue(RadioScriptGenerator.preservesForm(text, form: source, opening: opening))
        XCTAssertFalse(RadioScriptGenerator.preservesForm(text, form: source))
    }
}

private struct RadioFormStub: TCCCLLMBackend {
    let text: String
    let displayName = "Synthetic radio fixture"
    var availability: BackendAvailability { .available }
    func generate(instructions: String, prompt: String) async throws -> String { text }
}
