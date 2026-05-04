import Foundation
import TCCCDomain

struct ExtractedFact: Identifiable, Hashable {
    enum Kind: Hashable {
        case mechanism
        case hemorrhageLocation
        case hemorrhageIntervention
        case airwayStatus
        case airwayIntervention
        case respiration
        case breathSounds
        case pulse
        case skin
        case circulationIntervention
        case consciousness
        case pupils
        case hypothermia
        case vitalsHR
        case vitalsBP
        case vitalsSpO2
        case vitalsRR
        case vitalsGCS
        case vitalsTemp
        case vitalsCapRefill
        case classification
        case injury
        case intervention
        case pawsPain
        case pawsAntibiotics
        case pawsWounds
        case pawsSplinting

        var label: String {
            switch self {
            case .mechanism:               "MOI"
            case .hemorrhageLocation:      "LOC"
            case .hemorrhageIntervention:  "HEMO"
            case .airwayStatus:            "AIR"
            case .airwayIntervention:      "AIR INT"
            case .respiration:             "RESP"
            case .breathSounds:            "BS"
            case .pulse:                   "PULSE"
            case .skin:                    "SKIN"
            case .circulationIntervention: "IV"
            case .consciousness:           "AVPU"
            case .pupils:                  "PUPIL"
            case .hypothermia:             "HYPO"
            case .vitalsHR:                "HR"
            case .vitalsBP:                "BP"
            case .vitalsSpO2:              "SpO₂"
            case .vitalsRR:                "RR"
            case .vitalsGCS:               "GCS"
            case .vitalsTemp:              "TEMP"
            case .vitalsCapRefill:         "CAP RE"
            case .classification:          "CLASS"
            case .injury:                  "INJ"
            case .intervention:            "INT"
            case .pawsPain:                "PAIN"
            case .pawsAntibiotics:         "ABX"
            case .pawsWounds:              "WND"
            case .pawsSplinting:           "SPLT"
            }
        }

        var systemImage: String {
            switch self {
            case .mechanism:                "exclamationmark.triangle.fill"
            case .hemorrhageLocation:       "mappin"
            case .hemorrhageIntervention:   "drop.fill"
            case .airwayStatus, .airwayIntervention: "lungs"
            case .respiration, .breathSounds, .vitalsRR: "wind"
            case .pulse, .vitalsHR:         "heart.fill"
            case .skin:                     "hand.raised.fill"
            case .circulationIntervention, .intervention: "cross.case.fill"
            case .consciousness, .vitalsGCS, .pupils: "brain.head.profile"
            case .hypothermia:              "thermometer.snowflake"
            case .vitalsBP:                 "waveform.path.ecg"
            case .vitalsSpO2:               "lungs.fill"
            case .vitalsTemp:               "thermometer.medium"
            case .vitalsCapRefill:          "timer"
            case .classification:           "flag.fill"
            case .injury:                   "bandage.fill"
            case .pawsPain:                 "syringe"
            case .pawsAntibiotics:          "pills.fill"
            case .pawsWounds:               "bandage"
            case .pawsSplinting:            "ruler"
            }
        }

        var isHot: Bool {
            switch self {
            case .hemorrhageIntervention, .pawsPain, .pawsAntibiotics, .classification: true
            default: false
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let value: String
    let timestamp: Date
}

extension ExtractedFact {
    static func derive(from patient: PatientState?) -> [ExtractedFact] {
        guard let patient else { return [] }
        let ts = patient.timestampLastUpdate.map { Date(timeIntervalSince1970: $0) } ?? Date()
        var facts: [ExtractedFact] = []

        if let v = patient.mechanismOfInjury {
            facts.append(.init(kind: .mechanism, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.hemorrhageLocation {
            facts.append(.init(kind: .hemorrhageLocation, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.hemorrhageIntervention {
            facts.append(.init(kind: .hemorrhageIntervention, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.airwayStatus {
            facts.append(.init(kind: .airwayStatus, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.airwayIntervention {
            facts.append(.init(kind: .airwayIntervention, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.respirationStatus {
            facts.append(.init(kind: .respiration, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.breathSounds {
            facts.append(.init(kind: .breathSounds, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.pulseStatus {
            facts.append(.init(kind: .pulse, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.skinSigns {
            facts.append(.init(kind: .skin, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.circulationIntervention {
            facts.append(.init(kind: .circulationIntervention, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.consciousness {
            facts.append(.init(kind: .consciousness, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.pupilResponse {
            facts.append(.init(kind: .pupils, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.march.hypothermiaPrevention {
            facts.append(.init(kind: .hypothermia, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.vitals.hr {
            facts.append(.init(kind: .vitalsHR, value: "\(v)", timestamp: ts))
        }
        if let v = patient.vitals.bp {
            let suffix = v.palpated ? " P" : ""
            facts.append(.init(kind: .vitalsBP, value: "\(v.systolic)/\(v.diastolic)\(suffix)", timestamp: ts))
        }
        if let v = patient.vitals.spo2 {
            facts.append(.init(kind: .vitalsSpO2, value: "\(v)%", timestamp: ts))
        }
        if let v = patient.vitals.rr {
            facts.append(.init(kind: .vitalsRR, value: "\(v)", timestamp: ts))
        }
        if let v = patient.vitals.gcs {
            facts.append(.init(kind: .vitalsGCS, value: "\(v)", timestamp: ts))
        }
        if let v = patient.vitals.temperatureCelsius {
            facts.append(.init(kind: .vitalsTemp, value: String(format: "%.1f °C", v), timestamp: ts))
        }
        if let v = patient.vitals.capillaryRefillSeconds {
            facts.append(.init(kind: .vitalsCapRefill, value: String(format: "%.1f s", v), timestamp: ts))
        }
        if let v = patient.classification {
            facts.append(.init(kind: .classification, value: v.rawValue.uppercased(), timestamp: ts))
        }
        for inj in patient.injuries.prefix(4) {
            facts.append(.init(kind: .injury, value: inj.uppercased(), timestamp: ts))
        }
        if let v = patient.paws.pain {
            facts.append(.init(kind: .pawsPain, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.paws.antibiotics {
            facts.append(.init(kind: .pawsAntibiotics, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.paws.wounds {
            facts.append(.init(kind: .pawsWounds, value: v.uppercased(), timestamp: ts))
        }
        if let v = patient.paws.splinting {
            facts.append(.init(kind: .pawsSplinting, value: v.uppercased(), timestamp: ts))
        }

        return facts
    }
}
