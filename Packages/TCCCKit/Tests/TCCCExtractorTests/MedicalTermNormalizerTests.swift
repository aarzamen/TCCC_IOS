// MedicalTermNormalizerTests
//
// Each positive case is a sentence Apple Speech produced on device
// (2026-10-27 recording); each negative case guards against rewriting
// ordinary English that happens to contain the same words.

import XCTest
@testable import TCCCExtractor

final class MedicalTermNormalizerTests: XCTestCase {

    private let n = MedicalTermNormalizer()

    func testIsItTrueRateIsRespiratoryRate() {
        XCTAssertEqual(
            n.normalize("Is it true rate 16 his SPO2 is 96% he's he's screaming pain."),
            "respiratory rate 16 his SPO2 is 96% he's he's screaming pain.")
    }

    func testHerPenNextToGivingIsErtapenem() {
        XCTAssertEqual(
            n.normalize("I'm gonna give him her pen For the antibiotic and then I'm gonna give him Mobic"),
            "I'm gonna give him ertapenem For the antibiotic and then I'm gonna give him Mobic")
    }

    func testAPenHimAfterGaveIsErtapenem() {
        XCTAssertEqual(n.normalize("I gave him a pen him."), "I gave him ertapenem.")
    }

    func testAPenWithoutAGivingCueIsLeftAlone() {
        let text = "I used a pen to mark the tourniquet time on his forehead."
        XCTAssertEqual(n.normalize(text), text)
        let hers = "She handed me her pen so I could sign the card."
        XCTAssertEqual(n.normalize(hers), hers)
    }

    func testCueInTheNextSentenceDoesNotCount() {
        let text = "She handed me her pen. I gave him antibiotics."
        XCTAssertEqual(n.normalize(text), text)
    }

    func testEverythingElseIsUntouched() {
        let text = "Heart rate is 99 bpm. His blood pressure is 120/60. Respiratory rate 18."
        XCTAssertEqual(n.normalize(text), text)
    }

    func testEngineAppliesTheRepairBeforeExtraction() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Is it true rate 16 his SPO2 is 96%.")
        let p = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(p?.vitals.rr, 16)
        XCTAssertEqual(p?.vitals.spo2, 96)
    }
}
