// Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift
import Foundation
import TCCCDomain

extension PatientStateEngine {

    // MARK: - Log-derived deterministic facts (A6)

    /// A DD-1380-bindable fact derived from the encounter log, carrying the evidenceIds
    /// of the deterministicFact event that last set the (patientId, domain, field) tuple.
    public struct DerivedFact: Sendable, Equatable {
        public let patientId: String
        public let domain: String
        public let field: String
        public let value: String
        public let evidenceIds: [String]
    }

    /// Latest (domain, field) value per patient from deterministicFact events, with the
    /// evidenceIds of the event that set it. Only the DD-1380-bindable subset that maps
    /// to the GraniteSchemaValidator vocabulary is surfaced; deltas outside that subset
    /// are ignored for the packet (they still live in the log as audit).
    public nonisolated static func deterministicFacts(from log: EncounterLog) -> [DerivedFact] {
        var latest: [String: DerivedFact] = [:]   // key: "pid|domain|field"
        for case .deterministicFact(let p) in log.events {
            guard let mapped = vocabulary(for: p.delta) else { continue }
            let key = "\(p.patientId)|\(mapped.domain)|\(mapped.field)"
            latest[key] = DerivedFact(patientId: p.patientId, domain: mapped.domain,
                field: mapped.field, value: mapped.value, evidenceIds: p.evidenceIds)
        }
        return Array(latest.values).sorted { $0.field < $1.field }
    }

    /// Map a delta to the (domain, field, value) packet vocabulary, or nil if the
    /// delta is not a DD-1380-bindable fact.
    private nonisolated static func vocabulary(for delta: PatientStateDelta) -> (domain: String, field: String, value: String)? {
        switch delta {
        case .vitalsHR(let v?):                 return ("vitals", "heartRate", String(v))
        case .vitalsSpO2(let v?):               return ("vitals", "spo2", String(v))
        case .vitalsRR(let v?):                 return ("vitals", "respiratoryRate", String(v))
        case .vitalsBP(let v?):                 return ("vitals", "bloodPressure", "\(v.systolic)/\(v.diastolic)")
        case .hemorrhageLocation(let v?):       return ("march", "hemorrhageLocation", v)
        case .hemorrhageIntervention(let v?):   return ("march", "hemorrhageIntervention", v)
        case .airwayIntervention(let v?):       return ("march", "airwayIntervention", v)
        case .consciousness(let v?):            return ("march", "consciousness", v)
        case .hypothermiaPrevention(let v?):    return ("march", "hypothermiaPrevention", v)
        case .pawsPain(let v?):                 return ("paws", "pain", v)
        case .pawsAntibiotics(let v?):          return ("paws", "antibiotic", v)
        default:                                return nil
        }
    }

    // MARK: - Operator write application

    /// Apply one operator-vocabulary write. Pure field-set (no timestamp side effect);
    /// the engine and the projection own timestamp semantics around it.
    nonisolated static func applyWrite(_ write: PatientStateFieldWrite, to p: inout PatientState) {
        switch write {
        case .heartRate(let v):              p.vitals.hr = v
        case .spo2(let v):                   p.vitals.spo2 = v
        case .respiratoryRate(let v):        p.vitals.rr = v
        case .bloodPressure(let s, let d, let pal):
            p.vitals.bp = BloodPressure(systolic: s, diastolic: d, palpated: pal)
        case .hemorrhageLocation(let v):     p.march.hemorrhageLocation = v
        case .hemorrhageIntervention(let v): p.march.hemorrhageIntervention = v
        case .airwayIntervention(let v):     p.march.airwayIntervention = v
        case .consciousness(let v):          p.march.consciousness = v
        case .hypothermiaPrevention(let v):  p.march.hypothermiaPrevention = v
        case .pain(let v):                   p.paws.pain = v
        case .antibiotics(let v):            p.paws.antibiotics = v
        }
    }

    /// Apply one audit-grain delta. Direct field assignment is intentional — the
    /// value was produced by a validated extractor pass; re-validation would change it
    /// and break the inverse property.
    nonisolated static func applyDelta(_ delta: PatientStateDelta, to p: inout PatientState) {
        switch delta {
        case .mechanismOfInjury(let v):          p.mechanismOfInjury = v
        case .marchPhase(let v):                 p.marchPhase = v
        case .classification(let v):             p.classification = v
        case .timestampFirstMention(let v):      p.timestampFirstMention = v
        case .timestampLastUpdate(let v):        p.timestampLastUpdate = v
        case .appendInjury(let v):               p.injuries.append(v)
        case .setInjuries(let v):                p.injuries = v
        case .appendIntervention(let v):         p.interventions.append(v)
        case .setInterventions(let v):           p.interventions = v
        case .vitalsHR(let v):                   p.vitals.hr = v
        case .vitalsBP(let v):                   p.vitals.bp = v
        case .vitalsSpO2(let v):                 p.vitals.spo2 = v
        case .vitalsRR(let v):                   p.vitals.rr = v
        case .vitalsGCS(let v):                  p.vitals.gcs = v
        case .vitalsTemperatureCelsius(let v):   p.vitals.temperatureCelsius = v
        case .vitalsCapillaryRefillSeconds(let v): p.vitals.capillaryRefillSeconds = v
        case .hemorrhageIdentified(let v):       p.march.hemorrhageIdentified = v
        case .hemorrhageAssessed(let v):         p.march.hemorrhageAssessed = v
        case .hemorrhageLocation(let v):         p.march.hemorrhageLocation = v
        case .hemorrhageIntervention(let v):     p.march.hemorrhageIntervention = v
        case .hemorrhageEffective(let v):        p.march.hemorrhageEffective = v
        case .airwayStatus(let v):               p.march.airwayStatus = v
        case .airwayIntervention(let v):         p.march.airwayIntervention = v
        case .respirationStatus(let v):          p.march.respirationStatus = v
        case .respirationIntervention(let v):    p.march.respirationIntervention = v
        case .breathSounds(let v):               p.march.breathSounds = v
        case .pulseStatus(let v):                p.march.pulseStatus = v
        case .skinSigns(let v):                  p.march.skinSigns = v
        case .circulationIntervention(let v):    p.march.circulationIntervention = v
        case .consciousness(let v):              p.march.consciousness = v
        case .pupilResponse(let v):              p.march.pupilResponse = v
        case .hypothermiaPrevention(let v):      p.march.hypothermiaPrevention = v
        case .pawsPain(let v):                   p.paws.pain = v
        case .pawsAntibiotics(let v):            p.paws.antibiotics = v
        case .pawsWounds(let v):                 p.paws.wounds = v
        case .pawsSplinting(let v):              p.paws.splinting = v
        }
    }

    /// Total diff: `apply(diff(before, after)) == after`. Scalars/optionals emit a
    /// set-delta on change; collections emit per-element append deltas when `after`
    /// extends `before` as a prefix, else a whole-array set fallback.
    nonisolated static func diff(_ before: PatientState, _ after: PatientState) -> [PatientStateDelta] {
        var d: [PatientStateDelta] = []
        // PatientState scalars
        if before.mechanismOfInjury != after.mechanismOfInjury { d.append(.mechanismOfInjury(after.mechanismOfInjury)) }
        if before.marchPhase != after.marchPhase { d.append(.marchPhase(after.marchPhase)) }
        if before.classification != after.classification { d.append(.classification(after.classification)) }
        if before.timestampFirstMention != after.timestampFirstMention { d.append(.timestampFirstMention(after.timestampFirstMention)) }
        if before.timestampLastUpdate != after.timestampLastUpdate { d.append(.timestampLastUpdate(after.timestampLastUpdate)) }
        // Collections
        appendCollectionDiff(before.injuries, after.injuries, into: &d,
                             append: { .appendInjury($0) }, set: { .setInjuries($0) })
        appendCollectionDiff(before.interventions, after.interventions, into: &d,
                             append: { .appendIntervention($0) }, set: { .setInterventions($0) })
        // Vitals
        if before.vitals.hr != after.vitals.hr { d.append(.vitalsHR(after.vitals.hr)) }
        if before.vitals.bp != after.vitals.bp { d.append(.vitalsBP(after.vitals.bp)) }
        if before.vitals.spo2 != after.vitals.spo2 { d.append(.vitalsSpO2(after.vitals.spo2)) }
        if before.vitals.rr != after.vitals.rr { d.append(.vitalsRR(after.vitals.rr)) }
        if before.vitals.gcs != after.vitals.gcs { d.append(.vitalsGCS(after.vitals.gcs)) }
        if before.vitals.temperatureCelsius != after.vitals.temperatureCelsius { d.append(.vitalsTemperatureCelsius(after.vitals.temperatureCelsius)) }
        if before.vitals.capillaryRefillSeconds != after.vitals.capillaryRefillSeconds { d.append(.vitalsCapillaryRefillSeconds(after.vitals.capillaryRefillSeconds)) }
        // MARCHState
        if before.march.hemorrhageIdentified != after.march.hemorrhageIdentified { d.append(.hemorrhageIdentified(after.march.hemorrhageIdentified)) }
        if before.march.hemorrhageAssessed != after.march.hemorrhageAssessed { d.append(.hemorrhageAssessed(after.march.hemorrhageAssessed)) }
        if before.march.hemorrhageLocation != after.march.hemorrhageLocation { d.append(.hemorrhageLocation(after.march.hemorrhageLocation)) }
        if before.march.hemorrhageIntervention != after.march.hemorrhageIntervention { d.append(.hemorrhageIntervention(after.march.hemorrhageIntervention)) }
        if before.march.hemorrhageEffective != after.march.hemorrhageEffective { d.append(.hemorrhageEffective(after.march.hemorrhageEffective)) }
        if before.march.airwayStatus != after.march.airwayStatus { d.append(.airwayStatus(after.march.airwayStatus)) }
        if before.march.airwayIntervention != after.march.airwayIntervention { d.append(.airwayIntervention(after.march.airwayIntervention)) }
        if before.march.respirationStatus != after.march.respirationStatus { d.append(.respirationStatus(after.march.respirationStatus)) }
        if before.march.respirationIntervention != after.march.respirationIntervention { d.append(.respirationIntervention(after.march.respirationIntervention)) }
        if before.march.breathSounds != after.march.breathSounds { d.append(.breathSounds(after.march.breathSounds)) }
        if before.march.pulseStatus != after.march.pulseStatus { d.append(.pulseStatus(after.march.pulseStatus)) }
        if before.march.skinSigns != after.march.skinSigns { d.append(.skinSigns(after.march.skinSigns)) }
        if before.march.circulationIntervention != after.march.circulationIntervention { d.append(.circulationIntervention(after.march.circulationIntervention)) }
        if before.march.consciousness != after.march.consciousness { d.append(.consciousness(after.march.consciousness)) }
        if before.march.pupilResponse != after.march.pupilResponse { d.append(.pupilResponse(after.march.pupilResponse)) }
        if before.march.hypothermiaPrevention != after.march.hypothermiaPrevention { d.append(.hypothermiaPrevention(after.march.hypothermiaPrevention)) }
        // PAWS
        if before.paws.pain != after.paws.pain { d.append(.pawsPain(after.paws.pain)) }
        if before.paws.antibiotics != after.paws.antibiotics { d.append(.pawsAntibiotics(after.paws.antibiotics)) }
        if before.paws.wounds != after.paws.wounds { d.append(.pawsWounds(after.paws.wounds)) }
        if before.paws.splinting != after.paws.splinting { d.append(.pawsSplinting(after.paws.splinting)) }
        return d
    }

    private nonisolated static func appendCollectionDiff<Element: Equatable>(
        _ before: [Element], _ after: [Element], into d: inout [PatientStateDelta],
        append: (Element) -> PatientStateDelta, set: ([Element]) -> PatientStateDelta
    ) {
        guard before != after else { return }
        if after.count >= before.count && Array(after.prefix(before.count)) == before {
            for element in after.suffix(after.count - before.count) { d.append(append(element)) }
        } else {
            d.append(set(after))
        }
    }

    /// Fold the log into per-patient state by replaying recorded deltas + operator
    /// writes in order. Pure: never re-runs extractors, never reads actor state.
    nonisolated static func project(_ log: EncounterLog) -> [String: PatientState] {
        var patients: [String: PatientState] = ["PATIENT_1": PatientState(patientId: "PATIENT_1")]
        func ensure(_ pid: String) {
            if patients[pid] == nil { patients[pid] = PatientState(patientId: pid) }
        }
        for event in log.events {
            switch event {
            case .asrSegment, .operatorRejectedFact, .lifecycle:
                continue
            case .deterministicFact(let p):
                ensure(p.patientId)
                var s = patients[p.patientId]!
                applyDelta(p.delta, to: &s)
                patients[p.patientId] = s
            case .operatorAcceptedFact(let p):
                ensure(p.patientId)
                guard let write = p.write else { continue }
                var s = patients[p.patientId]!
                applyWrite(write, to: &s)
                s.timestampLastUpdate = p.timestampUnix
                patients[p.patientId] = s
            }
        }
        return patients
    }
}
