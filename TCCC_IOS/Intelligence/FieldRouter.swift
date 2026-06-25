// TCCC_IOS/Intelligence/FieldRouter.swift
import Foundation
import TCCCDomain
import TCCCExtractor

/// Why a `(domain, field, value)` triple could not become a typed mutation.
/// Every rejection is explicit and surfaced/logged — never a silent drop.
enum FieldRouteRejection: Equatable {
    case unknownDomain(String)
    case unknownField(String)
    case valueOutOfRubricRange(field: String, value: String)
    case noSetterWired(domain: String, field: String)
}

enum FieldRouteOutcome: Equatable {
    case mutation(PatientStateFieldWrite)
    case rejected(FieldRouteRejection)
}

/// Rubric-bounded translator from an LLM-originated `(domain, field, value)` string
/// triple to a typed `PatientStateFieldWrite`, or an explicit rejection. This is the
/// boundary that makes "LLM-never-mutates-state" structural: only a wired, in-range,
/// rubric-known triple yields a mutation; everything else is rejected.
enum FieldRouter {
    static let knownDomains: Set<String> = ["march", "vitals", "paws", "medevac", "dd1380"]

    static func route(domain: String, field: String, value: String?) -> FieldRouteOutcome {
        guard knownDomains.contains(domain) else { return .rejected(.unknownDomain(domain)) }
        // "known field" oracle = the existing schema-validator allow-list.
        guard GraniteSchemaValidator.allowedFields.contains(field) else {
            return .rejected(.unknownField(field))
        }
        guard let value, !value.isEmpty else {
            return .rejected(.valueOutOfRubricRange(field: field, value: value ?? "nil"))
        }
        switch (domain, field) {
        case ("vitals", "heartRate"):
            guard let n = Int(value), Vitals.hrRange.contains(n) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.heartRate(n))
        case ("vitals", "spo2"):
            guard let n = Int(value), Vitals.spo2Range.contains(n) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.spo2(n))
        case ("vitals", "respiratoryRate"):
            guard let n = Int(value), Vitals.rrRange.contains(n) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.respiratoryRate(n))
        case ("vitals", "bloodPressure"):
            let parts = value.split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let s = parts[0], let d = parts[1],
                  (0...300).contains(s), (0...300).contains(d) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.bloodPressure(systolic: s, diastolic: d, palpated: false))
        case ("march", "hemorrhageLocation"):     return .mutation(.hemorrhageLocation(value))
        case ("march", "hemorrhageIntervention"): return .mutation(.hemorrhageIntervention(value))
        case ("march", "airwayIntervention"):     return .mutation(.airwayIntervention(value))
        case ("march", "consciousness"):
            let avpu = Set(["A", "V", "P", "U", "Alert", "Voice", "Pain", "Unresponsive"])
            guard avpu.contains(value) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.consciousness(value))
        case ("march", "hypothermiaPrevention"):  return .mutation(.hypothermiaPrevention(value))
        case ("paws", "pain"):                    return .mutation(.pain(value))
        case ("paws", "antibiotics"), ("paws", "antibiotic"): return .mutation(.antibiotics(value))
        default:
            return .rejected(.noSetterWired(domain: domain, field: field))
        }
    }
}
