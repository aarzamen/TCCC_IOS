import XCTest
import PDFKit
import TCCCReports
@testable import TCCC_IOS

final class DD1380OfficialFormFillerTests: XCTestCase {

    private func sampleCard() -> DD1380CardData {
        var c = DD1380CardData()
        c.nameLastFirst = "DOE, J."
        c.last4 = "4471"
        c.battleRosterNumber = "JD4471"
        c.evacCategory = .urgent
        c.sex = .male
        c.unit = "2/75 RGR"
        c.allergies = "PCN"
        c.dateDDMMMYY = "14-NOV-23"
        c.timeHHMM = "2213Z"
        c.mechanisms.gsw = true
        c.tourniquets = [DD1380TourniquetEntry(limb: .rightLeg, type: "CAT", timeHHMM: "2213")]
        c.sectionCReadings = [
            DD1380SectionCReading(timeHHMM: "2213", pulse: "96 radial", bloodPressure: "120/80",
                                  respiratoryRate: "18", spo2: "97", avpu: "A", pain: "6"),
            DD1380SectionCReading(timeHHMM: "2225", pulse: "88", bloodPressure: "118/78",
                                  respiratoryRate: "16", spo2: "98", avpu: "A", pain: "4"),
        ]
        c.treatments.tqExtremity = true
        c.treatments.tqTypeText = "CAT"
        c.treatments.dressingHemostatic = true
        c.medications = [DD1380MedicationEntry(category: .analgesic, name: "Ketamine", dose: "50 mg",
                                               route: "IM", timeHHMM: "2215")]
        c.otherTreatments.hypothermiaPrevention = true
        c.otherTreatments.hypothermiaType = "HPMK"
        c.notes = "Hemorrhage: right thigh\nInjuries: GSW right thigh"
        c.firstResponderName = "HAWK, SAM"
        c.firstResponderLast4 = "1234"
        return c
    }

    private func document(_ data: Data) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: data))
    }

    private func pageText(_ doc: PDFDocument, _ index: Int) -> String {
        doc.page(at: index)?.string ?? ""
    }

    func testTemplateFieldsMatchManifest() throws {
        let pdfURL = try XCTUnwrap(Bundle.main.url(forResource: DD1380OfficialForm.templateResource, withExtension: "pdf"))
        let jsonURL = try XCTUnwrap(Bundle.main.url(forResource: DD1380OfficialForm.manifestResource, withExtension: "json"))
        struct Field: Decodable { let name: String }
        let expected = Set(try JSONDecoder().decode([Field].self, from: Data(contentsOf: jsonURL)).map(\.name))
        let doc = try XCTUnwrap(PDFDocument(url: pdfURL))
        var names = Set<String>()
        for index in 0..<doc.pageCount {
            for annotation in doc.page(at: index)?.annotations ?? [] where annotation.type == "Widget" {
                if let name = annotation.fieldName { names.insert(name) }
            }
        }
        XCTAssertEqual(names, expected)
    }

    func testFilledFormIsFlattenedOfficialForm() throws {
        let doc = try document(DD1380OfficialFormFiller.render(sampleCard()))
        XCTAssertEqual(doc.pageCount, 2)
        for index in 0..<doc.pageCount {
            let widgets = doc.page(at: index)?.annotations.filter { $0.type == "Widget" } ?? []
            XCTAssertTrue(widgets.isEmpty, "page \(index) still has \(widgets.count) form fields")
        }
        let front = pageText(doc, 0)
        for expected in ["DD Form 1380, JUN 2014", "DOE, J.", "4471", "JD4471", "120", "80", "96 radial",
                         "2/75 RGR", "PCN"] {
            XCTAssertTrue(front.contains(expected), "front page lacks \(expected)")
        }
        let back = pageText(doc, 1)
        for expected in ["Ketamine", "HPMK", "HAWK, SAM", "Hemorrhage: right thigh"] {
            XCTAssertTrue(back.contains(expected), "back page lacks \(expected)")
        }
    }

    func testBlankCardStillRendersTheForm() throws {
        let doc = try document(DD1380OfficialFormFiller.render(DD1380CardData()))
        XCTAssertEqual(doc.pageCount, 2)
        XCTAssertTrue(pageText(doc, 0).contains("DD Form 1380, JUN 2014"))
        XCTAssertFalse(pageText(doc, 0).contains("NKDA"))
    }

    // JTS card guide (TCCC-CMC-SC-64, 15 MAY 2025): attach another DD 1380,
    // labelled #2, showing the casualty's name and unit.
    func testLongNotesAddALabelledSecondCard() throws {
        var card = sampleCard()
        card.notes = (1...15).map { "Note line \($0)" }.joined(separator: "\n")
        let doc = try document(DD1380OfficialFormFiller.render(card))
        XCTAssertEqual(doc.pageCount, 4, "original front and back, then card #2 front and back")
        XCTAssertTrue(pageText(doc, 1).contains(DD1380OfficialForm.continuationMarker(nextCard: 2)))
        XCTAssertFalse(pageText(doc, 0).contains("DD 1380 #2"), "the original is not labelled")
        let secondFront = pageText(doc, 2)
        for expected in ["DD 1380 #2", DD1380OfficialForm.edition, "DOE, J.", "2/75 RGR", "JD4471"] {
            XCTAssertTrue(secondFront.contains(expected), "card #2 front lacks \(expected)")
        }
        XCTAssertFalse(secondFront.contains("96 radial"), "clinical values are not repeated on card #2")
        let secondBack = pageText(doc, 3)
        XCTAssertTrue(secondBack.contains("DD 1380 #2"))
        XCTAssertTrue(secondBack.contains("Note line 15"), secondBack)
        // "Ketamine" is printed on every back ("e.g., Ketamine, Fentanyl"); the dose is ours.
        XCTAssertFalse(secondBack.contains("50 mg"), "meds are not repeated on card #2")
        for index in 0..<doc.pageCount {
            XCTAssertTrue(doc.page(at: index)?.annotations.filter { $0.type == "Widget" }.isEmpty == true)
        }
    }

    func testVeryLongNotesMakeNumberedCards() throws {
        var card = sampleCard()
        card.notes = (1...60).map { "Note line \($0)" }.joined(separator: "\n")
        let doc = try document(DD1380OfficialFormFiller.render(card))
        XCTAssertEqual(doc.pageCount % 2, 0, "every card has a front and a back")
        let cards = doc.pageCount / 2
        XCTAssertEqual(cards, DD1380OfficialForm.cardSet(for: card).count)
        let lastBack = pageText(doc, doc.pageCount - 1)
        XCTAssertTrue(lastBack.contains("DD 1380 #\(cards)"), lastBack)
        XCTAssertTrue(lastBack.contains("Note line 60"), lastBack)
        XCTAssertFalse(lastBack.contains("(continued on DD 1380"))
    }

    func testMissingTemplateThrows() {
        XCTAssertThrowsError(try DD1380OfficialFormFiller.render(sampleCard(), bundle: Bundle(for: Self.self))) { error in
            XCTAssertEqual(error as? DD1380FillError, .templateMissing)
        }
    }

    /// The real path: a demo transcript through the engine, the app's card
    /// builder and the official form. Writes the PDF for a visual check.
    @MainActor
    func testDemoScenarioFillsOfficialForm() async throws {
        let state = AppState()
        await state.loadDemoTranscript(DemoScenarios.scenario1)
        let card = try XCTUnwrap(state.makeDD1380Card())
        XCTAssertTrue(DD1380Readiness.evaluate(card: card).hasClinicalContent)
        // "Applying a tourniquet now, CAT tourniquet" → R Leg corner and the TQ Type line.
        XCTAssertEqual(card.tourniquets.first?.limb, .rightLeg)
        XCTAssertEqual(card.tourniquets.first?.type, "CAT")
        XCTAssertEqual(card.treatments.tqTypeText, "CAT")
        let data = try DD1380OfficialFormFiller.render(card)
        let doc = try document(data)
        XCTAssertGreaterThanOrEqual(doc.pageCount, 2)
        XCTAssertTrue(pageText(doc, 0).contains(DD1380OfficialForm.edition))
        XCTAssertTrue(pageText(doc, 0).contains("CAT"))
        XCTAssertTrue(pageText(doc, 1).contains("CAT"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DD1380_demo_scenario1.pdf")
        try data.write(to: url)
        print("DD1380_DEMO_PATH=\(url.path)")
    }

    /// Apple Speech segments from the first on-device recording (2026-10-27),
    /// verbatim, minus the identity sentence: facts the first export left off.
    @MainActor
    func testLiveRecordingFactsReachTheCard() async throws {
        let state = AppState()
        await state.loadDemoTranscript("""
            The patient is a actor duty male Gunshot went to the lower extremity he has learned oriented times for applying tourniquet To the left lower extremity above the knee
            I'm gonna go ahead and get a set of vitals Heart rate is 99 bpm. His blood pressure is 120/60.
            Is it true rate 16 his SPO2 is 96% he's he's screaming pain. He's an eight out of 10 pain. Established IV access in the right AC I'm doing a blood sweep. I don't see any massive hemorrhage anywhere his airways clear.
            """)
        let card = try XCTUnwrap(state.makeDD1380Card())
        XCTAssertEqual(card.tourniquets.first?.limb, .leftLeg)
        XCTAssertTrue(card.treatments.airwayIntact)
        XCTAssertEqual(card.sectionCReadings.last?.pain, "8")
        XCTAssertTrue(card.notes.contains("IV access established"), card.notes)
        let doc = try document(try DD1380OfficialFormFiller.render(card))
        XCTAssertFalse(pageText(doc, 1).contains("location unknown"))
    }

    /// Writes the sample for a visual check; prints its path.
    func testWritesSampleForVisualCheck() throws {
        var card = sampleCard()
        card.notes += "\n" + (1...14).map { "Extra note line \($0) for the continuation page check." }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DD1380_sample.pdf")
        try DD1380OfficialFormFiller.render(card).write(to: url)
        print("DD1380_SAMPLE_PATH=\(url.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
