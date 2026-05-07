import Foundation

enum GraniteReportKind: String, Codable, Sendable, Equatable, Hashable {
    case nineLine
    case zmist
    case dd1380
}

enum GraniteReportCritiqueIssue: String, Codable, Sendable, Equatable, Hashable {
    case missingEvidence
    case conflict
    case impossibleValue
    case unsupportedClaim
    case omission
}

enum GraniteReportCritiqueSeverity: String, Codable, Sendable, Equatable, Hashable {
    case review
    case caution
    case blocking
}

struct GraniteReportCritiqueFinding: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let reportField: String
    let issue: GraniteReportCritiqueIssue
    let severity: GraniteReportCritiqueSeverity
    let evidenceIds: [String]
    let suggestedReviewPrompt: String
}

struct GraniteReportCritique: Codable, Sendable, Equatable {
    let packetId: String
    let reportKind: GraniteReportKind
    let findings: [GraniteReportCritiqueFinding]
    let modelSelfCheck: String
}

enum GraniteReportCritiqueValidationError: Sendable, Equatable, Hashable {
    case missingEvidenceIds(findingId: String)
    case unknownEvidenceId(findingId: String, evidenceId: String)
    case unknownReportField(field: String)
    case directRewriteRequested(findingId: String)
}

struct GraniteReportCritiqueValidationResult: Sendable, Equatable {
    let acceptedFindings: [GraniteReportCritiqueFinding]
    let errors: Set<GraniteReportCritiqueValidationError>

    var isAccepted: Bool { errors.isEmpty }
}

enum GraniteReportCritiqueValidator {
    static func validate(
        _ critique: GraniteReportCritique,
        knownEvidenceIds: Set<String>
    ) -> GraniteReportCritiqueValidationResult {
        var errors: Set<GraniteReportCritiqueValidationError> = []
        let allowedFields = allowedFields(for: critique.reportKind)

        for finding in critique.findings {
            if !allowedFields.contains(finding.reportField) {
                errors.insert(.unknownReportField(field: finding.reportField))
            }

            if finding.evidenceIds.isEmpty {
                errors.insert(.missingEvidenceIds(findingId: finding.id))
            }

            for evidenceId in finding.evidenceIds where !knownEvidenceIds.contains(evidenceId) {
                errors.insert(.unknownEvidenceId(findingId: finding.id, evidenceId: evidenceId))
            }

            if asksForDirectRewrite(finding.suggestedReviewPrompt) {
                errors.insert(.directRewriteRequested(findingId: finding.id))
            }
        }

        return GraniteReportCritiqueValidationResult(
            acceptedFindings: errors.isEmpty ? critique.findings : [],
            errors: errors
        )
    }

    private static func allowedFields(for kind: GraniteReportKind) -> Set<String> {
        switch kind {
        case .nineLine:
            return [
                "line1Location",
                "line2RadioFrequencyCallsign",
                "line3PatientsByPrecedence",
                "line4SpecialEquipment",
                "line5PatientsByType",
                "line6Security",
                "line7Marking",
                "line8NationalityStatus",
                "line9NBC"
            ]
        case .zmist:
            return [
                "mechanism",
                "injuries",
                "signsSymptoms",
                "treatments"
            ]
        case .dd1380:
            return [
                "battleRosterNumber",
                "evacuationPriority",
                "mechanismOfInjury",
                "injuryLocation",
                "vitalSigns",
                "treatments",
                "medications",
                "documentationForwarded"
            ]
        }
    }

    private static func asksForDirectRewrite(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("rewrite the report")
            || normalized.contains("replace the report")
            || normalized.contains("overwrite")
    }
}
