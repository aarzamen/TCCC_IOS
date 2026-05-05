// Phase3VocabularyTests
//
// Per 2026 sprint spec Phase 3: every new pattern has a unit test
// asserting the verbatim phrase from
// reference/rubric/extracted/march_paws_vocabulary_2026.json matches,
// and that the pattern does not over-match unrelated transcripts.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class Phase3VocabularyTests: XCTestCase {

    private let timestamp = Date(timeIntervalSince1970: 0)

    private func ctx(_ s: String, isNegated: Bool = false) -> ExtractionContext {
        ExtractionContext(
            originalText: s,
            normalizedText: s,
            sentence: s,
            timestamp: timestamp,
            currentPatientID: "PATIENT_1",
            isNegated: isNegated)
    }

    private func emptyState() -> PatientState {
        PatientState(patientId: "PATIENT_1")
    }

    // MARK: - 3.1 Suzetrigine (PAWS §11)

    func testSuzetrigineRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Gave Suzetrigine 100 mg PO."))
        XCTAssertEqual(s.paws.pain, "Suzetrigine administered")
    }

    func testSuzetrigineTwoBy50mgRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Suzetrigine, two 50 mg tablets."))
        XCTAssertEqual(s.paws.pain, "Suzetrigine administered")
    }

    func testSuzetrigineDoesNotOvermatch() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("She wore a sunset rig in the photo."))
        XCTAssertNil(s.paws.pain)
    }

    // MARK: - 3.3 Esketamine IN (PAWS §11)

    func testEsketamineRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Esketamine 14 mg IN."))
        XCTAssertEqual(s.paws.pain, "Esketamine administered")
    }

    func testEsketamine28mgRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Gave esketamine 28 mg intranasal."))
        XCTAssertEqual(s.paws.pain, "Esketamine administered")
    }

    func testEsketamineNotConfusedWithKetamine() {
        // Sentence contains both keywords; "esketamine" must beat "ketamine"
        // in the sub-classifier order.
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Esketamine, not ketamine, was administered."))
        XCTAssertEqual(s.paws.pain, "Esketamine administered")
    }

    func testKetamineStillRecognized() {
        // Regression: bare ketamine still matches the legacy descriptor.
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Ketamine 50 mg IM administered."))
        XCTAssertEqual(s.paws.pain, "Ketamine administered")
    }

    // MARK: - 3.4 Antibiotics 2026 (PAWS §12)

    func testCefadroxilRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Cefadroxil 1 g PO once a day."))
        XCTAssertEqual(s.paws.antibiotics, "Cefadroxil administered")
    }

    func testCephalexinRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Cephalexin 500 mg PO every 6 hours."))
        XCTAssertEqual(s.paws.antibiotics, "Cephalexin administered")
    }

    func testCeftriaxoneIVRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Ceftriaxone 2 g IV given."))
        XCTAssertEqual(s.paws.antibiotics, "Ceftriaxone administered")
    }

    func testCeftriaxoneIORecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Ceftriaxone 2 g IO administered."))
        XCTAssertEqual(s.paws.antibiotics, "Ceftriaxone administered")
    }

    func testMoxifloxacinStillRecognizedForBackCompat() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Gave moxifloxacin."))
        XCTAssertEqual(s.paws.antibiotics, "Moxifloxacin administered")
    }

    func testGenericAntibioticDescriptorWhenNoSpecificDrug() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Antibiotics administered."))
        XCTAssertEqual(s.paws.antibiotics, "Antibiotics administered")
    }

    // MARK: - 3.5 Tourniquet reposition (Hemorrhage §6)

    func testTourniquetRepositionEmitsConversion() {
        let h = HemorrhageExtractor()
        let s = h.apply(emptyState(),
                        context: ctx("Repositioning the tourniquet directly to the skin 2-3 inches above the bleeding site."))
        XCTAssertTrue(s.interventions.contains { $0.kind == .tourniquetConversion })
    }

    func testAppliedSecondTourniquetEmitsConversion() {
        let h = HemorrhageExtractor()
        let s = h.apply(emptyState(),
                        context: ctx("Applied a second tourniquet, then loosened the first tourniquet."))
        XCTAssertTrue(s.interventions.contains { $0.kind == .tourniquetConversion })
    }

    func testReplaceTourniquetEmitsConversionForBackCompat() {
        let h = HemorrhageExtractor()
        let s = h.apply(emptyState(),
                        context: ctx("Replacing the tourniquet now."))
        XCTAssertTrue(s.interventions.contains { $0.kind == .tourniquetConversion })
    }

    func testTourniquetRepositionDedupedAcrossSentences() {
        let h = HemorrhageExtractor()
        var s = emptyState()
        s = h.apply(s, context: ctx("Repositioning the tourniquet."))
        s = h.apply(s, context: ctx("Repositioning the tourniquet again."))
        let count = s.interventions.filter { $0.kind == .tourniquetConversion }.count
        XCTAssertEqual(count, 1)
    }

    func testGenericTourniquetMentionDoesNotEmitConversion() {
        // Initial application only — the conversion intervention should NOT
        // fire on a bare "tourniquet applied".
        let h = HemorrhageExtractor()
        let s = h.apply(emptyState(),
                        context: ctx("Applied tourniquet to the right thigh."))
        XCTAssertFalse(s.interventions.contains { $0.kind == .tourniquetConversion })
    }

    // MARK: - 3.9 Hypertonic saline + herniation signs (TBI §8)

    func testHypertonicSalineRecognized() {
        let t = TBIExtractor()
        let s = t.apply(emptyState(),
                        context: ctx("Gave hypertonic saline."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("hypertonic saline")
        })
    }

    func testHypertonicSaline250mlOf3Percent() {
        let t = TBIExtractor()
        let s = t.apply(emptyState(),
                        context: ctx("250 ml of 3% IV over 10 minutes."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("hypertonic saline")
        })
    }

    func testHypertonicSaline30mlOf234Percent() {
        let t = TBIExtractor()
        let s = t.apply(emptyState(),
                        context: ctx("30 ml of 23.4% pushed slowly."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("hypertonic saline")
        })
    }

    func testHypertonicSalineDoesNotOvermatch() {
        let t = TBIExtractor()
        let s = t.apply(emptyState(),
                        context: ctx("250 ml of normal saline given."))
        XCTAssertFalse(s.interventions.contains {
            $0.description.lowercased().contains("hypertonic saline")
        })
    }

    func testPosturingRecordedAsInjury() {
        let t = TBIExtractor()
        let s = t.apply(emptyState(),
                        context: ctx("Posturing on left side."))
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("posturing") })
    }

    func testDecorticatePosturingRecognized() {
        let t = TBIExtractor()
        let s = t.apply(emptyState(),
                        context: ctx("Decorticate posturing observed."))
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("posturing") })
    }

    func testAsymmetricPupilRecordedAsInjury() {
        let t = TBIExtractor()
        let s = t.apply(emptyState(),
                        context: ctx("Asymmetric pupils, left dilated."))
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("asymmetric pupil") })
    }

    // MARK: - 3.10 Calcium after transfusion (Circulation §6)

    func testCalciumGluconateRecognized() {
        let c = CirculationExtractor()
        let s = c.apply(emptyState(),
                        context: ctx("30 ml of 10% calcium gluconate IV."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("calcium")
        })
    }

    func testCalciumChlorideRecognized() {
        let c = CirculationExtractor()
        let s = c.apply(emptyState(),
                        context: ctx("10 ml of 10% calcium chloride IV."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("calcium")
        })
    }

    func testOneGramCalciumRecognized() {
        let c = CirculationExtractor()
        let s = c.apply(emptyState(),
                        context: ctx("1 g calcium IO post-transfusion."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("calcium")
        })
    }

    func testCalciumDoesNotOvermatch() {
        let c = CirculationExtractor()
        let s = c.apply(emptyState(),
                        context: ctx("Patient takes a daily calcium-D3 supplement."))
        // Bare "calcium" without IV/IO/gluconate/chloride/1g context should
        // not trigger the post-transfusion intervention. The pattern requires
        // a clinical specifier.
        XCTAssertFalse(s.interventions.contains {
            $0.description.lowercased().contains("post-transfusion")
        })
    }

    // MARK: - 3.8 Airway 2026 vocabulary (§4)

    func testRecoveryPositionRecognized() {
        let a = AirwayExtractor()
        let s = a.apply(emptyState(),
                        context: ctx("Placed unconscious casualty in the recovery position."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("recovery position")
        })
    }

    func testHeadTiltedBackRecognized() {
        let a = AirwayExtractor()
        let s = a.apply(emptyState(),
                        context: ctx("Head tilted back, chin away from chest."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("recovery position")
        })
    }

    func testSuctionRecognized() {
        let a = AirwayExtractor()
        let s = a.apply(emptyState(),
                        context: ctx("Used suction to clear the airway."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("suction")
        })
    }

    func testEtco2CapnographyRecognized() {
        let a = AirwayExtractor()
        let s = a.apply(emptyState(),
                        context: ctx("Verified placement with continuous EtCO2 capnography."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("etco2")
        })
    }

    func testBougieAidedOpenStillTriggersCric() {
        let a = AirwayExtractor()
        let s = a.apply(emptyState(),
                        context: ctx("Performed bougie-aided open surgical cricothyroidotomy."))
        XCTAssertEqual(s.march.airwayIntervention, "Surgical cricothyroidotomy")
    }

    func testStandardOpenSurgicalRecognizedAsCric() {
        let a = AirwayExtractor()
        let s = a.apply(emptyState(),
                        context: ctx("Standard open surgical technique with 6 mm internal diameter cannula."))
        XCTAssertEqual(s.march.airwayIntervention, "Surgical cricothyroidotomy")
    }

    func testSuctionWordBoundaryDoesNotMatchSubsetWords() {
        // The pattern is \\bsuction(?:ed|ing)?\\b — must not match
        // "destruction" or "instruction" etc.
        let a = AirwayExtractor()
        let s = a.apply(emptyState(),
                        context: ctx("Following the instruction set carefully."))
        XCTAssertFalse(s.interventions.contains {
            $0.description.lowercased().contains("suction")
        })
    }
}
