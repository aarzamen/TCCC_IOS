import Foundation

/// MARCH assessment state for a single patient.
///
/// Mirrors `state.py:236–301` (`MARCHState` frozen dataclass). Field names,
/// optionality, and meaning are preserved from the Python source.
public struct MARCHState: Sendable, Codable, Equatable, Hashable {

    // M - Massive Hemorrhage
    public let hemorrhageIdentified: Bool
    /// True if hemorrhage was explicitly checked (even if none found).
    public let hemorrhageAssessed: Bool
    /// e.g. "right leg", "bilateral arms".
    public let hemorrhageLocation: String?
    /// e.g. "tourniquet applied".
    public let hemorrhageIntervention: String?
    public let hemorrhageEffective: Bool?

    // A - Airway
    /// e.g. "patent", "compromised", "obstructed".
    public let airwayStatus: String?
    /// e.g. "NPA inserted", "surgical cric".
    public let airwayIntervention: String?

    // R - Respiration
    /// e.g. "normal", "labored", "absent".
    public let respirationStatus: String?
    /// e.g. "chest seal", "needle decompression".
    public let respirationIntervention: String?
    /// e.g. "bilateral equal", "diminished left".
    public let breathSounds: String?

    // C - Circulation
    /// e.g. "strong radial", "weak radial", "absent radial".
    public let pulseStatus: String?
    /// e.g. "warm dry", "cool clammy", "pale".
    public let skinSigns: String?
    /// e.g. "IV access", "blood products".
    public let circulationIntervention: String?

    // H - Head/Hypothermia
    /// AVPU: Alert, Voice, Pain, Unresponsive.
    public let consciousness: String?
    public let pupilResponse: String?
    /// e.g. "hypothermia wrap applied".
    public let hypothermiaPrevention: String?

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
