import XCTest
@testable import TCCC_IOS

@MainActor
final class GraniteReportCritiqueTests: XCTestCase {
    func testValidNineLineCritiqueIsAcceptedAsReviewOnlyFinding() {
        let critique = GraniteReportCritique(
            packetId: "packet-1",
            reportKind: .nineLine,
            findings: [
                .init(
                    id: "critique-1",
                    reportField: "line1Location",
                    issue: .missingEvidence,
                    severity: .blocking,
                    evidenceIds: ["seg-1"],
                    suggestedReviewPrompt: "Verify Line 1 location before transmit."
                )
            ],
            modelSelfCheck: "review only"
        )

        let result = GraniteReportCritiqueValidator.validate(
            critique,
            knownEvidenceIds: ["seg-1"]
        )

        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.acceptedFindings.count, 1)
    }

    func testCritiqueRejectsEvidenceFreeFindings() {
        let critique = GraniteReportCritique(
            packetId: "packet-1",
            reportKind: .zmist,
            findings: [
                .init(
                    id: "critique-1",
                    reportField: "treatments",
                    issue: .unsupportedClaim,
                    severity: .review,
                    evidenceIds: [],
                    suggestedReviewPrompt: "Ask whether treatment was actually documented."
                )
            ],
            modelSelfCheck: "review only"
        )

        let result = GraniteReportCritiqueValidator.validate(
            critique,
            knownEvidenceIds: ["seg-1"]
        )

        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.errors.contains(.missingEvidenceIds(findingId: "critique-1")))
    }

    func testCritiqueRejectsUnknownFieldsAndRewritePrompts() {
        let critique = GraniteReportCritique(
            packetId: "packet-1",
            reportKind: .dd1380,
            findings: [
                .init(
                    id: "critique-1",
                    reportField: "freeTextSummary",
                    issue: .conflict,
                    severity: .review,
                    evidenceIds: ["seg-1"],
                    suggestedReviewPrompt: "Rewrite the report with this better summary."
                )
            ],
            modelSelfCheck: "review only"
        )

        let result = GraniteReportCritiqueValidator.validate(
            critique,
            knownEvidenceIds: ["seg-1"]
        )

        XCTAssertTrue(result.errors.contains(.unknownReportField(field: "freeTextSummary")))
        XCTAssertTrue(result.errors.contains(.directRewriteRequested(findingId: "critique-1")))
    }
}
