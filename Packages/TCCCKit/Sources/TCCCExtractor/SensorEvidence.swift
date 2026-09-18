import Foundation
import TCCCDomain

/// An operator's association applies only to one live connection and encounter.
/// Restoring its audit record never restores permission to ingest new readings.
public struct SensorAssociationPayload: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable { case associated, revoked }

    public let id: String
    public let associationID: String
    public let patientId: String
    public let timestampUnix: Double
    public let deviceID: String
    public let deviceName: String
    public let connectionID: UUID
    public let encounterID: UUID
    /// Index of the original association in the encounter log. Operator decisions
    /// after this fence protect their fields until another explicit association.
    public let eventFence: Int
    public let kind: Kind
}

public enum SensorVitalField: String, Sendable, Codable, Hashable {
    case pulseRate, spo2

    static func matching(_ write: PatientStateFieldWrite) -> SensorVitalField? {
        switch write {
        case .heartRate: return .pulseRate
        case .spo2: return .spo2
        default: return nil
        }
    }

    static func matching(_ delta: PatientStateDelta) -> SensorVitalField? {
        switch delta {
        case .vitalsHR: return .pulseRate
        case .vitalsSpO2: return .spo2
        default: return nil
        }
    }

    static func matching(alias: String) -> SensorVitalField? {
        let normalized = alias.lowercased().replacingOccurrences(of: "₂", with: "2")
            .filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "hr", "heartrate", "pulse", "pulserate", "pulsebpm", "pulseratebpm": return .pulseRate
        case "spo2", "oxygensaturation", "oxygensat", "saturation", "o2sat", "o2saturation": return .spo2
        default: return nil
        }
    }
}

public enum SensorObservationDisposition: String, Sendable, Codable {
    case recorded
    case partiallyProtected
    case operatorProtected
    case unavailable
    case unsupportedEncoding
    case noUsableValues
    case stale
    case outOfOrder
    case invalidTiming
}

public enum SensorReviewStatus: String, Sendable, Codable {
    case unvalidatedConsumerSensor
}

public enum SensorObservationTimeBasis: String, Sendable, Codable {
    case receipt
    case deviceAcquisition
}

public struct SensorObservationUnits: Sendable, Codable, Equatable {
    public enum Unit: String, Sendable, Codable { case beatsPerMinute, percent }
    public let pulseRate: Unit
    public let spo2: Unit

    public init() {
        pulseRate = .beatsPerMinute
        spo2 = .percent
    }
}

/// One complete, immutable audit record: original decoded evidence and exactly
/// the deltas applied at ingestion. Replay does not reinterpret device bytes.
public struct SensorObservationPayload: Sendable, Codable, Equatable {
    public let id: String
    public let patientId: String
    /// Time the engine records the observation. The sample retains its distinct
    /// receipt and optional device-acquisition timestamps.
    public let timestampUnix: Double
    public let associationID: String
    public let reading: PulseOximeterReading
    public let waveforms: [PulseOximeterWaveform]
    /// Nil in older event files; an empty array has the same meaning.
    public let auxiliaryFrames: [PulseOximeterRawFrame]?
    public let appliedDeltas: [PatientStateDelta]
    public let disposition: SensorObservationDisposition
    public let protectedFields: [SensorVitalField]
    public let reviewStatus: SensorReviewStatus
    public let units: SensorObservationUnits

    public var observationTime: Date { reading.acquiredAt ?? reading.receivedAt }
    public var timeBasis: SensorObservationTimeBasis {
        reading.acquiredAt == nil ? .receipt : .deviceAcquisition
    }

    /// Only values from this sample which actually entered state. Building a
    /// Section C column from this avoids carrying old BP/RR/AVPU values forward.
    public var appliedVitals: Vitals {
        var vitals = Vitals()
        for delta in appliedDeltas {
            switch delta {
            case .vitalsHR(let value): vitals.hr = value
            case .vitalsSpO2(let value): vitals.spo2 = value
            default: break
            }
        }
        return vitals
    }

    public var hasAppliedVitals: Bool {
        appliedDeltas.contains { SensorVitalField.matching($0) != nil }
    }
}
