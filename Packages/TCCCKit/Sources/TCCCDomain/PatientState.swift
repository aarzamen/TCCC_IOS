import Foundation

/// Complete state for a single patient.
///
/// Mirrors `state.py:304–317` (`PatientState` frozen dataclass). Two
/// principled departures from the Python source:
///
/// 1. `vitals` is a typed `Vitals` struct rather than a `dict` (per the iOS
///    design brief — see `CLAUDE.md` "Conventions").
/// 2. `paws` is promoted to a top-level field with its own struct. In Python
///    PAWS findings are scattered into the `interventions` list; the design
///    brief asks for PAWS as its own first-class assessment block.
///
/// All other fields preserve Python field names, optionality, and defaults.
public struct PatientState: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// e.g. "PATIENT_1", "PATIENT_2".
    public let patientId: String
    /// e.g. "IED blast", "GSW", "fall".
    public let mechanismOfInjury: String?
    public let march: MARCHState
    public let vitals: Vitals
    public let interventions: [Intervention]
    /// List of injuries (fractures, wounds, etc.).
    public let injuries: [String]
    /// Current MARCH phase being assessed. Defaults to massive ("M") to match
    /// the Python `march_phase: str = "M"`.
    public let marchPhase: MarchPhase
    public let classification: Classification?
    public let paws: PAWSAssessment
    /// POSIX seconds since epoch. Mirrors Python `Optional[float]`.
    public let timestampFirstMention: Double?
    public let timestampLastUpdate: Double?

    public var id: String { patientId }

    public init(
        patientId: String,
        mechanismOfInjury: String? = nil,
        march: MARCHState = MARCHState(),
        vitals: Vitals = Vitals(),
        interventions: [Intervention] = [],
        injuries: [String] = [],
        marchPhase: MarchPhase = .massive,
        classification: Classification? = nil,
        paws: PAWSAssessment = PAWSAssessment(),
        timestampFirstMention: Double? = nil,
        timestampLastUpdate: Double? = nil
    ) {
        self.patientId = patientId
        self.mechanismOfInjury = mechanismOfInjury
        self.march = march
        self.vitals = vitals
        self.interventions = interventions
        self.injuries = injuries
        self.marchPhase = marchPhase
        self.classification = classification
        self.paws = paws
        self.timestampFirstMention = timestampFirstMention
        self.timestampLastUpdate = timestampLastUpdate
    }
}
