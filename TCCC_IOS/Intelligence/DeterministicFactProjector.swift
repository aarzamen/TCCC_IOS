// TCCC_IOS/Intelligence/DeterministicFactProjector.swift
import Foundation
import TCCCDomain

/// Projects the engine's current `PatientState` into `[DeterministicFact]` so the
/// hot-seat packet carries the deterministic ground truth as context. Field names
/// match the `GraniteSchemaValidator.allowedFields` vocabulary so they round-trip
/// through the `FieldRouter`. Evidence linkage is best-effort this cycle (empty
/// `evidenceIds`) — a debt explicitly gated on the future EncounterEvent log.
enum DeterministicFactProjector {
    static func project(_ state: PatientState) -> [DeterministicFact] {
        var facts: [DeterministicFact] = []
        var idx = 0
        func add(_ domain: String, _ field: String, _ value: String?, _ extractor: String) {
            guard let value, !value.isEmpty else { return }
            idx += 1
            facts.append(DeterministicFact(
                id: "det-\(idx)", patientId: state.patientId, domain: domain, field: field,
                value: value, evidenceIds: [], extractor: extractor, confidence: .high))
        }
        if let hr = state.vitals.hr  { add("vitals", "heartRate", String(hr), "VitalsExtractor") }
        if let s = state.vitals.spo2 { add("vitals", "spo2", String(s), "VitalsExtractor") }
        if let rr = state.vitals.rr  { add("vitals", "respiratoryRate", String(rr), "VitalsExtractor") }
        if let bp = state.vitals.bp  { add("vitals", "bloodPressure", "\(bp.systolic)/\(bp.diastolic)", "VitalsExtractor") }
        add("march", "hemorrhageLocation", state.march.hemorrhageLocation, "HemorrhageExtractor")
        add("march", "hemorrhageIntervention", state.march.hemorrhageIntervention, "HemorrhageExtractor")
        add("march", "airwayIntervention", state.march.airwayIntervention, "AirwayExtractor")
        add("march", "consciousness", state.march.consciousness, "TBIExtractor")
        add("march", "hypothermiaPrevention", state.march.hypothermiaPrevention, "HypothermiaExtractor")
        add("paws", "pain", state.paws.pain, "PAWSExtractor")
        add("paws", "antibiotic", state.paws.antibiotics, "PAWSExtractor")
        return facts
    }
}
