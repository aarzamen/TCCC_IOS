import XCTest
import CoreGraphics
import TCCCReports
@testable import TCCC_IOS

final class DD1380PDFRendererTests: XCTestCase {

    private func sampleCard() -> DD1380CardData {
        var c = DD1380CardData()
        c.nameLastFirst = "DOE, J."
        c.last4 = "4471"
        c.battleRosterNumber = "JD4471"
        c.evacCategory = .urgent
        c.unit = "2/75 RGR"
        c.allergies = "NKDA"
        c.dateDDMMMYY = "14-NOV-23"
        c.timeHHMM = "2213Z"
        c.mechanisms.gsw = true
        c.tourniquets = [DD1380TourniquetEntry(limb: .rightLeg, type: nil, timeHHMM: "2213")]
        c.sectionCReadings = [
            DD1380SectionCReading(timeHHMM: "2213", pulse: "96", bloodPressure: "120/80",
                                  respiratoryRate: "18", spo2: "97", avpu: "A"),
            DD1380SectionCReading(timeHHMM: "2225", pulse: "88", bloodPressure: "118/78",
                                  respiratoryRate: "16", spo2: "98", avpu: "A"),
        ]
        c.treatments.tqExtremity = true
        c.medications = [DD1380MedicationEntry(category: .analgesic, name: "Ketamine 50mg IM", timeHHMM: "2215")]
        c.otherTreatments.hypothermiaPrevention = true
        c.otherTreatments.hypothermiaType = "HPMK"
        c.notes = "Hemorrhage: right thigh\nInjuries: GSW right thigh"
        c.firstResponderName = "HAWK-06"
        return c
    }

    func testRenderProducesNonEmptyData() throws {
        let data = try DD1380PDFRenderer.render(sampleCard())
        XCTAssertFalse(data.isEmpty)
    }

    func testRenderHasTwoPages() throws {
        let data = try DD1380PDFRenderer.render(sampleCard())
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let doc = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(doc.numberOfPages, 2)
    }

    func testRenderEmptyCardDoesNotCrash() throws {
        let data = try DD1380PDFRenderer.render(DD1380CardData())
        XCTAssertFalse(data.isEmpty)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        XCTAssertEqual(CGPDFDocument(provider)?.numberOfPages, 2)
    }

    func testRenderLongNotesDoesNotCrash() throws {
        var c = sampleCard()
        c.notes = String(repeating: "Long note line with clinical detail. ", count: 200)
        let data = try DD1380PDFRenderer.render(c)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        XCTAssertEqual(CGPDFDocument(provider)?.numberOfPages, 2)
    }
}
