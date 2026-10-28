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

    func testLongNotesAddContinuationPage() throws {
        var card = sampleCard()
        card.notes = (1...40).map { "Note line \($0)" }.joined(separator: "\n")
        let doc = try document(DD1380OfficialFormFiller.render(card))
        XCTAssertEqual(doc.pageCount, 3)
        XCTAssertTrue(pageText(doc, 1).contains(DD1380OfficialForm.continuationMarker))
        let continuation = pageText(doc, 2)
        XCTAssertTrue(continuation.contains("Note line 40"), continuation)
        XCTAssertTrue(continuation.contains("JD4471"), continuation)
    }

    func testVeryLongNotesSpanSeveralContinuationPages() throws {
        var card = sampleCard()
        card.notes = (1...200).map { "Note line \($0)" }.joined(separator: "\n")
        let doc = try document(DD1380OfficialFormFiller.render(card))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 6)
        let last = pageText(doc, doc.pageCount - 1)
        XCTAssertTrue(last.contains("Note line 200"), last)
        XCTAssertFalse(last.contains(DD1380OfficialForm.continuationMarker))
        let all = (2..<doc.pageCount).map { pageText(doc, $0) }.joined(separator: "\n")
        for n in [11, 60, 61, 120, 199] {
            XCTAssertTrue(all.contains("Note line \(n)\n") || all.contains("Note line \(n)"), "line \(n) missing")
        }
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
        let data = try DD1380OfficialFormFiller.render(card)
        let doc = try document(data)
        XCTAssertGreaterThanOrEqual(doc.pageCount, 2)
        XCTAssertTrue(pageText(doc, 0).contains(DD1380OfficialForm.edition))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DD1380_demo_scenario1.pdf")
        try data.write(to: url)
        print("DD1380_DEMO_PATH=\(url.path)")
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
