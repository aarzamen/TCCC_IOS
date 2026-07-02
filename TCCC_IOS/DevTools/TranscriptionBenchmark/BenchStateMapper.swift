import Foundation
import TCCCDomain

/// Renders the engine's PatientState into the flat [String: String] the
/// ExtractionScorer expects. Keys must match valdez_alley.json's
/// fieldExpectations.
enum BenchStateMapper {
    static func map(_ state: PatientState?) -> [String: String] {
        guard let state else { return [:] }
        var out: [String: String] = [:]
        if let moi = state.mechanismOfInjury { out["moi"] = moi.lowercased() }
        if let hr = state.vitals.hr { out["hr"] = String(hr) }
        if let bp = state.vitals.bp { out["bp"] = "\(bp.systolic)/\(bp.diastolic)" }
        if let rr = state.vitals.rr { out["rr"] = String(rr) }
        if let spo2 = state.vitals.spo2 { out["spo2"] = String(spo2) }
        if let classification = state.classification {
            out["classification"] = String(describing: classification).lowercased()
        }
        if !state.interventions.isEmpty {
            out["interventions"] = state.interventions
                .map { "\(String(describing: $0.kind)) \($0.description)" }
                .joined(separator: "; ")
                .lowercased()
        }
        return out
    }
}
