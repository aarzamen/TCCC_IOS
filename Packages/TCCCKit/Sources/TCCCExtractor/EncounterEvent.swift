// Packages/TCCCKit/Sources/TCCCExtractor/EncounterEvent.swift
import Foundation
import TCCCDomain

/// A typed, audit-grain representation of a single mutation to `PatientState`.
/// Spans every writable field of `PatientState` and its nested structs so that
/// `apply(diff(before, after)) == after` holds for any extractor output.
public enum PatientStateDelta: Sendable, Codable, Equatable {
    // PatientState scalars
    case mechanismOfInjury(String?)
    case marchPhase(MarchPhase)
    case classification(Classification?)
    case timestampFirstMention(Double?)
    case timestampLastUpdate(Double?)
    // PatientState collections
    case appendInjury(String)
    case setInjuries([String])
    case appendIntervention(Intervention)
    case setInterventions([Intervention])
    // Vitals
    case vitalsHR(Int?)
    case vitalsBP(BloodPressure?)
    case vitalsSpO2(Int?)
    case vitalsRR(Int?)
    case vitalsGCS(Int?)
    case vitalsTemperatureCelsius(Double?)
    case vitalsCapillaryRefillSeconds(Double?)
    // MARCHState
    case hemorrhageIdentified(Bool)
    case hemorrhageAssessed(Bool)
    case hemorrhageLocation(String?)
    case hemorrhageIntervention(String?)
    case hemorrhageEffective(Bool?)
    case airwayStatus(String?)
    case airwayIntervention(String?)
    case respirationStatus(String?)
    case respirationIntervention(String?)
    case breathSounds(String?)
    case pulseStatus(String?)
    case skinSigns(String?)
    case circulationIntervention(String?)
    case consciousness(String?)
    case pupilResponse(String?)
    case hypothermiaPrevention(String?)
    // PAWS
    case pawsPain(String?)
    case pawsAntibiotics(String?)
    case pawsWounds(String?)
    case pawsSplinting(String?)
}

public struct ASRSegmentPayload: Sendable, Codable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let text: String
    public let backend: String
    public let isFinal: Bool
    public init(id: String, patientId: String, timestampUnix: Double, text: String, backend: String, isFinal: Bool) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix
        self.text = text; self.backend = backend; self.isFinal = isFinal
    }
}

public struct DeterministicFactPayload: Sendable, Codable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let delta: PatientStateDelta
    public let evidenceIds: [String]
    public let extractor: String
    public init(id: String, patientId: String, timestampUnix: Double, delta: PatientStateDelta, evidenceIds: [String], extractor: String) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix
        self.delta = delta; self.evidenceIds = evidenceIds; self.extractor = extractor
    }
}

public struct OperatorDecisionPayload: Sendable, Codable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let write: PatientStateFieldWrite?   // accepted+routable: applied write; rejected/unroutable: nil
    public let sourceFactId: String?
    public let domain: String
    public let field: String
    public let rawValue: String?
    public init(id: String, patientId: String, timestampUnix: Double, write: PatientStateFieldWrite?, sourceFactId: String?, domain: String, field: String, rawValue: String?) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix
        self.write = write; self.sourceFactId = sourceFactId
        self.domain = domain; self.field = field; self.rawValue = rawValue
    }
}

public struct LifecyclePayload: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable { case encounterStarted, encounterEnded, archived }
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let kind: Kind
    public init(id: String, patientId: String, timestampUnix: Double, kind: Kind) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix; self.kind = kind
    }
}

/// One immutable record in the encounter log.
public enum EncounterEvent: Sendable, Codable, Equatable, Identifiable {
    case asrSegment(ASRSegmentPayload)
    case deterministicFact(DeterministicFactPayload)
    case operatorAcceptedFact(OperatorDecisionPayload)
    case operatorRejectedFact(OperatorDecisionPayload)
    case lifecycle(LifecyclePayload)

    public var id: String {
        switch self {
        case .asrSegment(let p): return p.id
        case .deterministicFact(let p): return p.id
        case .operatorAcceptedFact(let p), .operatorRejectedFact(let p): return p.id
        case .lifecycle(let p): return p.id
        }
    }
    public var patientId: String {
        switch self {
        case .asrSegment(let p): return p.patientId
        case .deterministicFact(let p): return p.patientId
        case .operatorAcceptedFact(let p), .operatorRejectedFact(let p): return p.patientId
        case .lifecycle(let p): return p.patientId
        }
    }
    public var timestampUnix: Double {
        switch self {
        case .asrSegment(let p): return p.timestampUnix
        case .deterministicFact(let p): return p.timestampUnix
        case .operatorAcceptedFact(let p), .operatorRejectedFact(let p): return p.timestampUnix
        case .lifecycle(let p): return p.timestampUnix
        }
    }
}

/// Append-only canonical record of one casualty's encounter.
public struct EncounterLog: Sendable, Codable, Equatable {
    public private(set) var events: [EncounterEvent]
    public init(events: [EncounterEvent] = []) { self.events = events }
    public mutating func append(_ event: EncounterEvent) { events.append(event) }
}
