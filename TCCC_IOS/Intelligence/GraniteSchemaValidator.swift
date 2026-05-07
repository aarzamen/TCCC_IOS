import Foundation

enum GraniteValidationError: Sendable, Equatable, Hashable {
    case unknownPatient(patientId: String)
    case missingEvidenceIds(factId: String)
    case unknownEvidenceId(factId: String, evidenceId: String)
    case unknownField(field: String)
    case impossibleValue(field: String, value: String)
}

struct GraniteValidationResult: Sendable, Equatable {
    let acceptedFacts: [GraniteCandidateFact]
    let conflicts: [GraniteConflict]
    let errors: Set<GraniteValidationError>

    var isAccepted: Bool { errors.isEmpty }
}

enum GraniteSchemaValidator {
    private static let allowedFields: Set<String> = [
        "airway",
        "airwayIntervention",
        "allergies",
        "antibiotic",
        "bloodPressure",
        "breathing",
        "burns",
        "capillaryRefill",
        "casualtyCategory",
        "consciousness",
        "evacuationPriority",
        "heartRate",
        "hemorrhageIntervention",
        "hemorrhageLocation",
        "hypothermiaPrevention",
        "injuryMechanism",
        "medication",
        "mentalStatus",
        "pain",
        "patientId",
        "pulse",
        "respiratoryRate",
        "signsAndSymptoms",
        "spo2",
        "tourniquetTime",
        "treatment",
        "vitalTime"
    ]

    static func validate(
        _ patch: GraniteCandidatePatch,
        knownEvidenceIds: Set<String>,
        knownPatientIds: Set<String>
    ) -> GraniteValidationResult {
        var errors: Set<GraniteValidationError> = []

        if !knownPatientIds.contains(patch.patientId) {
            errors.insert(.unknownPatient(patientId: patch.patientId))
        }

        for fact in patch.candidateFacts {
            validatePatient(fact.patientId, knownPatientIds: knownPatientIds, errors: &errors)
            validateField(fact.field, errors: &errors)
            validateEvidence(
                factId: fact.id,
                evidenceIds: fact.evidenceIds,
                knownEvidenceIds: knownEvidenceIds,
                allowsNoEvidence: fact.value == nil && fact.confidence == .unknown,
                errors: &errors
            )
            validateValue(field: fact.field, value: fact.value, errors: &errors)
        }

        for conflict in patch.conflicts {
            validatePatient(conflict.patientId, knownPatientIds: knownPatientIds, errors: &errors)
            validateField(conflict.field, errors: &errors)
            validateEvidence(
                factId: conflict.id,
                evidenceIds: conflict.evidenceIds,
                knownEvidenceIds: knownEvidenceIds,
                allowsNoEvidence: false,
                errors: &errors
            )
        }

        return GraniteValidationResult(
            acceptedFacts: errors.isEmpty ? patch.candidateFacts : [],
            conflicts: patch.conflicts,
            errors: errors
        )
    }

    private static func validatePatient(
        _ patientId: String,
        knownPatientIds: Set<String>,
        errors: inout Set<GraniteValidationError>
    ) {
        if !knownPatientIds.contains(patientId) {
            errors.insert(.unknownPatient(patientId: patientId))
        }
    }

    private static func validateField(
        _ field: String,
        errors: inout Set<GraniteValidationError>
    ) {
        if !allowedFields.contains(field) {
            errors.insert(.unknownField(field: field))
        }
    }

    private static func validateEvidence(
        factId: String,
        evidenceIds: [String],
        knownEvidenceIds: Set<String>,
        allowsNoEvidence: Bool,
        errors: inout Set<GraniteValidationError>
    ) {
        if evidenceIds.isEmpty && !allowsNoEvidence {
            errors.insert(.missingEvidenceIds(factId: factId))
        }
        for evidenceId in evidenceIds where !knownEvidenceIds.contains(evidenceId) {
            errors.insert(.unknownEvidenceId(factId: factId, evidenceId: evidenceId))
        }
    }

    private static func validateValue(
        field: String,
        value: String?,
        errors: inout Set<GraniteValidationError>
    ) {
        guard let value else { return }

        switch field {
        case "heartRate", "pulse":
            validateInteger(value, field: field, range: 0...300, errors: &errors)
        case "respiratoryRate":
            validateInteger(value, field: field, range: 0...80, errors: &errors)
        case "spo2":
            validateInteger(value, field: field, range: 0...100, errors: &errors)
        case "bloodPressure":
            validateBloodPressure(value, errors: &errors)
        default:
            break
        }
    }

    private static func validateInteger(
        _ value: String,
        field: String,
        range: ClosedRange<Int>,
        errors: inout Set<GraniteValidationError>
    ) {
        guard let intValue = Int(value), range.contains(intValue) else {
            errors.insert(.impossibleValue(field: field, value: value))
            return
        }
    }

    private static func validateBloodPressure(
        _ value: String,
        errors: inout Set<GraniteValidationError>
    ) {
        let parts = value.split(separator: "/")
        guard parts.count == 2,
              let systolic = Int(parts[0]),
              let diastolic = Int(parts[1]),
              (40...300).contains(systolic),
              (20...200).contains(diastolic) else {
            errors.insert(.impossibleValue(field: "bloodPressure", value: value))
            return
        }
    }
}
