import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class MOIExtractorTests: XCTestCase {

    private let extractor = MOIExtractor()

    private func context(_ sentence: String, isNegated: Bool = false) -> ExtractionContext {
        ExtractionContext(
            originalText: sentence,
            normalizedText: sentence,
            sentence: sentence,
            timestamp: Date(),
            currentPatientID: "PATIENT_1",
            isNegated: isNegated
        )
    }

    private func empty() -> PatientState { PatientState(patientId: "PATIENT_1") }

    func testGSWFromGunshot() {
        let result = extractor.apply(empty(), context: context("Gunshot wound to the right thigh."))
        XCTAssertEqual(result.mechanismOfInjury, "GSW")
    }

    func testGSWFromGSWAcronym() {
        let result = extractor.apply(empty(), context: context("Looks like a GSW upper right thigh."))
        XCTAssertEqual(result.mechanismOfInjury, "GSW")
    }

    func testGSWFromBullet() {
        let result = extractor.apply(empty(), context: context("Bullet entry wound to lower abdomen."))
        XCTAssertEqual(result.mechanismOfInjury, "GSW")
    }

    func testIEDBlast() {
        let result = extractor.apply(empty(), context: context("Two casualties from an IED blast."))
        XCTAssertEqual(result.mechanismOfInjury, "IED blast")
    }

    func testBareBlast() {
        let result = extractor.apply(empty(), context: context("Casualty from a blast."))
        XCTAssertEqual(result.mechanismOfInjury, "IED blast")
    }

    func testShrapnel() {
        let result = extractor.apply(empty(), context: context("Multiple shrapnel injuries to the legs."))
        XCTAssertEqual(result.mechanismOfInjury, "Shrapnel/fragmentation")
    }

    func testKnifeLaceration() {
        let result = extractor.apply(empty(), context: context("Marine cut himself opening an MRE — knife laceration to the left palm."))
        XCTAssertEqual(result.mechanismOfInjury, "Penetrating trauma")
    }

    func testFall() {
        let result = extractor.apply(empty(), context: context("He went down hard, just fell."))
        XCTAssertEqual(result.mechanismOfInjury, "Fall")
    }

    func testMVA() {
        let result = extractor.apply(empty(), context: context("Vehicle crash, two casualties from the JLTV."))
        XCTAssertEqual(result.mechanismOfInjury, "MVA")
    }

    func testDoesNotOverwriteExistingMOI() {
        var state = empty()
        state.mechanismOfInjury = "GSW"
        let result = extractor.apply(state, context: context("There was also a fall."))
        XCTAssertEqual(result.mechanismOfInjury, "GSW")
    }

    func testNoMOIInSentenceLeavesUnchanged() {
        let result = extractor.apply(empty(), context: context("Patient is alert and oriented."))
        XCTAssertNil(result.mechanismOfInjury)
    }

    func testNegatedSentenceStillSetsMOI() {
        // Python `_extract_moi` ignores the negation flag. We mirror this so
        // sentences like "No head injury, he just fell." still set MOI to Fall.
        let result = extractor.apply(empty(), context: context("No gunshot wound visible.", isNegated: true))
        XCTAssertEqual(result.mechanismOfInjury, "GSW")
    }

    func testWordBoundaryBlast() {
        let result = extractor.apply(empty(), context: context("Sandblasted area is downwind."))
        XCTAssertNil(result.mechanismOfInjury)
    }
}
