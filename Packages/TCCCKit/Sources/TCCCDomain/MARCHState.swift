import Foundation

/// MARCH assessment state for a single patient.
///
/// Mirrors `state.py:236–301` (`MARCHState` frozen dataclass). Field names,
/// optionality, and meaning are preserved from the Python source.
public struct MARCHState: Sendable, Codable, Equatable, Hashable {

    // M - Massive Hemorrhage
    public var hemorrhageIdentified: Bool
    /// True if hemorrhage was explicitly checked (even if none found).
    public var hemorrhageAssessed: Bool
    /// e.g. "right leg", "bilateral arms".
    public var hemorrhageLocation: String?
    /// e.g. "tourniquet applied".
    public var hemorrhageIntervention: String?
    public var hemorrhageEffective: Bool?

    // A - Airway
    /// e.g. "patent", "compromised", "obstructed".
    public var airwayStatus: String?
    /// e.g. "NPA inserted", "surgical cric".
    public var airwayIntervention: String?

    // R - Respiration
    /// e.g. "normal", "labored", "absent".
    public var respirationStatus: String?
    /// e.g. "chest seal", "needle decompression".
    public var respirationIntervention: String?
    /// e.g. "bilateral equal", "diminished left".
    public var breathSounds: String?

    // C - Circulation
    /// e.g. "strong radial", "weak radial", "absent radial".
    public var pulseStatus: String?
    /// e.g. "warm dry", "cool clammy", "pale".
    public var skinSigns: String?
    /// e.g. "IV access", "blood products".
    public var circulationIntervention: String?

    // H - Head/Hypothermia
    /// AVPU: Alert, Voice, Pain, Unresponsive.
    public var consciousness: String?
    public var pupilResponse: String?
    /// e.g. "hypothermia wrap applied".
    public var hypothermiaPrevention: String?

    public init(
        hemorrhageIdentified: Bool = false,
        hemorrhageAssessed: Bool = false,
        hemorrhageLocation: String? = nil,
        hemorrhageIntervention: String? = nil,
        hemorrhageEffective: Bool? = nil,
        airwayStatus: String? = nil,
        airwayIntervention: String? = nil,
        respirationStatus: String? = nil,
        respirationIntervention: String? = nil,
        breathSounds: String? = nil,
        pulseStatus: String? = nil,
        skinSigns: String? = nil,
        circulationIntervention: String? = nil,
        consciousness: String? = nil,
        pupilResponse: String? = nil,
        hypothermiaPrevention: String? = nil
    ) {
        self.hemorrhageIdentified = hemorrhageIdentified
        self.hemorrhageAssessed = hemorrhageAssessed
        self.hemorrhageLocation = hemorrhageLocation
        self.hemorrhageIntervention = hemorrhageIntervention
        self.hemorrhageEffective = hemorrhageEffective
        self.airwayStatus = airwayStatus
        self.airwayIntervention = airwayIntervention
        self.respirationStatus = respirationStatus
        self.respirationIntervention = respirationIntervention
        self.breathSounds = breathSounds
        self.pulseStatus = pulseStatus
        self.skinSigns = skinSigns
        self.circulationIntervention = circulationIntervention
        self.consciousness = consciousness
        self.pupilResponse = pupilResponse
        self.hypothermiaPrevention = hypothermiaPrevention
    }

    /// True when every MARCH phase has at least an in-progress assessment.
    /// PAWS rendering is gated on this — per 2026 sprint spec 2.1, PAWS
    /// phases stay dormant ("—") until MARCH has been assessed at all.
    public var allPhasesAssessed: Bool {
        MarchPhase.allCases.allSatisfy {
            getPhaseStatus($0) != .notAssessed
        }
    }

    // MARK: - Hypothermia / TBI sub-phase status (2026 split)
    //
    // The 2026 TCCC Guidelines treat Hypothermia (§7) and TBI (§8) as
    // distinct sections. The legacy MARCH-H slot has been split into two
    // sub-rows in the UI; these computed statuses drive that split. The
    // `head` MarchPhase remains the umbrella for backward compatibility.

    /// Status of the Hypothermia (H-Hypo) sub-phase per 2026 §7.
    public var hypothermiaPhaseStatus: PhaseStatus {
        hypothermiaPrevention != nil ? .done : .notAssessed
    }

    /// Status of the TBI (H-TBI) sub-phase per 2026 §8. Considers AVPU
    /// (consciousness) and pupil response — both are TBI-relevant findings.
    public var tbiPhaseStatus: PhaseStatus {
        if consciousness != nil || pupilResponse != nil { return .done }
        return .notAssessed
    }

    /// Status indicator for a MARCH phase. Mirrors `state.py:get_phase_status`
    /// (lines 266–301).
    public func getPhaseStatus(_ phase: MarchPhase) -> PhaseStatus {
        switch phase {
        case .massive:
            if hemorrhageIntervention != nil {
                return .done
            } else if hemorrhageAssessed {
                // Hemorrhage was checked and none found — still counts as assessed.
                return .done
            } else if hemorrhageIdentified || hemorrhageLocation != nil {
                return .inProgress
            }
            return .notAssessed
        case .airway:
            if airwayStatus != nil {
                return .done
            } else if airwayIntervention != nil {
                return .inProgress
            }
            return .notAssessed
        case .respiration:
            if breathSounds != nil || respirationStatus != nil {
                return .done
            } else if respirationIntervention != nil {
                return .inProgress
            }
            return .notAssessed
        case .circulation:
            if pulseStatus != nil || skinSigns != nil {
                return .done
            } else if circulationIntervention != nil {
                return .inProgress
            }
            return .notAssessed
        case .head:
            if consciousness != nil || pupilResponse != nil {
                return .done
            } else if hypothermiaPrevention != nil {
                return .inProgress
            }
            return .notAssessed
        }
    }
}
