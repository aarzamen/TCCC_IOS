import Foundation
import TCCCDomain

// MARK: - DD Form 1380 field model
//
// A pure, deterministic representation of the DD Form 1380 (JUN 2014) FIELDS —
// not the UI, not the rendered layout. Keyed to the §A–H field inventory in
// `reference/rubric/extracted/dd1380_field_inventory.json`. Filled
// deterministically from structured `PatientState` + app metadata by
// `DD1380Mapper`; the LLM never touches it. Unknown fields stay blank.

/// §A / §D EVAC precedence. The form's allowed values are Urgent / Priority /
/// Routine; `Urgent Surgical` collapses to Urgent, `Expectant` has no DD1380
/// box (→ left blank).
public enum DD1380EvacCategory: String, Sendable, Codable, Equatable {
    case urgent = "Urgent"
    case priority = "Priority"
    case routine = "Routine"
}

/// §A GENDER checkbox.
public enum DD1380Sex: String, Sendable, Codable, Equatable {
    case male = "M"
    case female = "F"
}

/// §B Mechanism of Injury multi-checkbox. Values are the form's exact allowed
/// set (per the rubric field inventory), plus free `otherText` for "Other".
public struct DD1380MechanismFlags: Sendable, Codable, Equatable {
    public var artillery = false
    public var blunt = false
    public var burn = false
    public var fall = false
    public var grenade = false
    public var gsw = false
    public var ied = false
    public var landmine = false
    public var mvc = false
    public var rpg = false
    public var other = false
    public var otherText = ""

    public init() {}

    public var anyChecked: Bool {
        artillery || blunt || burn || fall || grenade || gsw || ied
            || landmine || mvc || rpg || other
    }
}

/// §B tourniquet corner.
public enum DD1380Limb: String, Sendable, Codable, Equatable {
    case rightArm = "R Arm"
    case leftArm = "L Arm"
    case rightLeg = "R Leg"
    case leftLeg = "L Leg"
}

/// §B tourniquet entry. `type` is left nil unless explicitly extracted — the
/// mapper never infers a TQ device. `locationText` carries the raw hemorrhage
/// location when it can't be resolved to a specific limb corner.
public struct DD1380TourniquetEntry: Sendable, Codable, Equatable {
    public var limb: DD1380Limb?
    public var type: String?
    public var timeHHMM: String?
    public var locationText: String?

    public init(limb: DD1380Limb? = nil, type: String? = nil,
                timeHHMM: String? = nil, locationText: String? = nil) {
        self.limb = limb
        self.type = type
        self.timeHHMM = timeHHMM
        self.locationText = locationText
    }
}

/// §B body-diagram mark. Reserved for confident anatomical marks; today the
/// mapper leaves this empty and routes injury locations to Notes instead of
/// inventing precise coordinates.
public struct DD1380InjuryMark: Sendable, Codable, Equatable {
    public var label: String
    public var isFront: Bool

    public init(label: String, isFront: Bool) {
        self.label = label
        self.isFront = isFront
    }
}

/// §C one timestamped vital-sign column (the grid holds up to 4). Stored as
/// pre-formatted display strings so the renderer never re-parses clinical data.
public struct DD1380SectionCReading: Sendable, Codable, Equatable {
    public var timeHHMM: String
    public var pulse: String?            // rate (+ location if known)
    public var bloodPressure: String?    // "120/80"
    public var respiratoryRate: String?
    public var spo2: String?
    public var avpu: String?             // A / V / P / U
    public var pain: String?             // 0–10

    public init(timeHHMM: String, pulse: String? = nil, bloodPressure: String? = nil,
                respiratoryRate: String? = nil, spo2: String? = nil,
                avpu: String? = nil, pain: String? = nil) {
        self.timeHHMM = timeHHMM
        self.pulse = pulse
        self.bloodPressure = bloodPressure
        self.respiratoryRate = respiratoryRate
        self.spo2 = spo2
        self.avpu = avpu
        self.pain = pain
    }
}

/// §E Fluid / Blood Product repeating row (name, volume, route, time).
public struct DD1380FluidEntry: Sendable, Codable, Equatable {
    public var name: String
    public var volume: String?
    public var route: String?
    public var timeHHMM: String?

    public init(name: String, volume: String? = nil, route: String? = nil, timeHHMM: String? = nil) {
        self.name = name
        self.volume = volume
        self.route = route
        self.timeHHMM = timeHHMM
    }
}

/// §F medication category (Analgesic / Antibiotic / Other rows).
public enum DD1380MedCategory: String, Sendable, Codable, Equatable {
    case analgesic
    case antibiotic
    case other
}

/// §F MEDS repeating row (name, dose, route, time).
public struct DD1380MedicationEntry: Sendable, Codable, Equatable {
    public var category: DD1380MedCategory
    public var name: String
    public var dose: String?
    public var route: String?
    public var timeHHMM: String?

    public init(category: DD1380MedCategory, name: String, dose: String? = nil,
                route: String? = nil, timeHHMM: String? = nil) {
        self.category = category
        self.name = name
        self.dose = dose
        self.route = route
        self.timeHHMM = timeHHMM
    }
}

/// §E treatment checkboxes (TQ category, Dressing, Airway, Breathing).
public struct DD1380TreatmentFlags: Sendable, Codable, Equatable {
    // C — hemorrhage control TQ category
    public var tqExtremity = false
    public var tqJunctional = false
    public var tqTruncal = false
    public var tqTypeText = ""
    // Dressing
    public var dressingHemostatic = false
    public var dressingPressure = false
    public var dressingOther = false
    public var dressingTypeText = ""
    // A — airway
    public var airwayIntact = false
    public var airwayNPA = false
    public var airwayCRIC = false
    public var airwayETTube = false
    public var airwaySGA = false
    public var airwayTypeText = ""
    // B — breathing
    public var breathingO2 = false
    public var breathingNeedleD = false
    public var breathingChestTube = false
    public var breathingChestSeal = false
    public var breathingTypeText = ""

    public init() {}
}

/// §F OTHER row checkboxes.
public struct DD1380OtherTreatmentFlags: Sendable, Codable, Equatable {
    public var combatPillPack = false
    public var eyeShieldRight = false
    public var eyeShieldLeft = false
    public var splint = false
    public var hypothermiaPrevention = false
    public var hypothermiaType = ""

    public init() {}
}

/// The whole DD Form 1380, §A–H, as deterministic field values.
public struct DD1380CardData: Sendable, Codable, Equatable {
    // §A — front header
    public var battleRosterNumber = ""
    public var evacCategory: DD1380EvacCategory?
    public var nameLastFirst = ""
    public var last4 = ""
    public var sex: DD1380Sex?
    public var dateDDMMMYY = ""
    public var timeHHMM = ""          // 24h + L/Z suffix
    public var service = ""
    public var unit = ""
    public var allergies = ""

    // §B — mechanism / injury / tourniquets
    public var mechanisms = DD1380MechanismFlags()
    public var injuryMarks: [DD1380InjuryMark] = []
    public var tourniquets: [DD1380TourniquetEntry] = []

    // §C — vital-sign grid (up to 4 columns)
    public var sectionCReadings: [DD1380SectionCReading] = []

    // §E — treatments
    public var treatments = DD1380TreatmentFlags()
    public var fluids: [DD1380FluidEntry] = []
    public var bloodProducts: [DD1380FluidEntry] = []

    // §F — meds + other
    public var medications: [DD1380MedicationEntry] = []
    public var otherTreatments = DD1380OtherTreatmentFlags()

    // §G — notes
    public var notes = ""

    // §H — first responder
    public var firstResponderName = ""
    public var firstResponderLast4 = ""

    public init() {}
}

// MARK: - Mapper input DTO

/// Pure input to `DD1380Mapper` — clinical state plus the app-owned metadata
/// the engine does not carry (identity, operator, encounter timing). Keeps
/// TCCCKit free of any app-target dependency.
public struct DD1380MapperInput: Sendable, Equatable {
    public let patient: PatientState
    public let casualtyId: String
    public let casualtyName: String
    public let casualtyLast4: String
    public let casualtySex: DD1380Sex?
    public let casualtyService: String
    public let casualtyUnit: String
    public let casualtyAllergies: String
    public let operatorName: String
    public let operatorLast4: String
    public let sectionCReadings: [DD1380SectionCReading]
    public let encounterStart: Date
    public let now: Date

    public init(patient: PatientState, casualtyId: String, casualtyName: String,
                casualtyLast4: String, casualtySex: DD1380Sex?, casualtyService: String,
                casualtyUnit: String, casualtyAllergies: String, operatorName: String,
                operatorLast4: String, sectionCReadings: [DD1380SectionCReading],
                encounterStart: Date, now: Date) {
        self.patient = patient
        self.casualtyId = casualtyId
        self.casualtyName = casualtyName
        self.casualtyLast4 = casualtyLast4
        self.casualtySex = casualtySex
        self.casualtyService = casualtyService
        self.casualtyUnit = casualtyUnit
        self.casualtyAllergies = casualtyAllergies
        self.operatorName = operatorName
        self.operatorLast4 = operatorLast4
        self.sectionCReadings = sectionCReadings
        self.encounterStart = encounterStart
        self.now = now
    }
}

// MARK: - Readiness

/// Deterministic readiness assessment for a filled `DD1380CardData`. Informs
/// the UI detail/warning. A partially complete DD1380 is better than none, so
/// this NEVER blocks generation — it only reports what is present/missing.
public struct DD1380ReadinessResult: Sendable, Equatable {
    public let hasPatientIdentity: Bool
    public let hasDateTime: Bool
    public let hasClinicalContent: Bool
    public let hasSectionCVital: Bool
    public let hasFirstResponder: Bool
    public let criticalMissing: [String]

    public init(hasPatientIdentity: Bool, hasDateTime: Bool, hasClinicalContent: Bool,
                hasSectionCVital: Bool, hasFirstResponder: Bool, criticalMissing: [String]) {
        self.hasPatientIdentity = hasPatientIdentity
        self.hasDateTime = hasDateTime
        self.hasClinicalContent = hasClinicalContent
        self.hasSectionCVital = hasSectionCVital
        self.hasFirstResponder = hasFirstResponder
        self.criticalMissing = criticalMissing
    }
}

public enum DD1380Readiness {
    public static func evaluate(card: DD1380CardData) -> DD1380ReadinessResult {
        let hasIdentity = !card.nameLastFirst.isEmpty || !card.last4.isEmpty
            || !card.battleRosterNumber.isEmpty
        let hasDateTime = !card.dateDDMMMYY.isEmpty && !card.timeHHMM.isEmpty
        let hasClinical = card.mechanisms.anyChecked
            || !card.tourniquets.isEmpty
            || !card.sectionCReadings.isEmpty
            || !card.medications.isEmpty
            || !card.fluids.isEmpty
            || !card.bloodProducts.isEmpty
            || hasAnyTreatment(card.treatments)
            || hasAnyOther(card.otherTreatments)
            || !card.notes.isEmpty
        let hasSectionC = card.sectionCReadings.contains { reading in
            reading.pulse != nil || reading.bloodPressure != nil
                || reading.respiratoryRate != nil || reading.spo2 != nil
                || reading.avpu != nil || reading.pain != nil
        }
        let hasResponder = !card.firstResponderName.isEmpty || !card.firstResponderLast4.isEmpty

        // Required §A fields per the rubric, reported when blank.
        var missing: [String] = []
        if card.battleRosterNumber.isEmpty { missing.append("Battle Roster #") }
        if card.evacCategory == nil { missing.append("EVAC") }
        if card.nameLastFirst.isEmpty { missing.append("Name") }
        if card.last4.isEmpty { missing.append("Last 4") }
        if card.sex == nil { missing.append("Gender") }
        if card.dateDDMMMYY.isEmpty { missing.append("Date") }
        if card.timeHHMM.isEmpty { missing.append("Time") }
        if card.service.isEmpty { missing.append("Service") }
        if card.unit.isEmpty { missing.append("Unit") }
        if card.allergies.isEmpty { missing.append("Allergies") }
        if card.firstResponderName.isEmpty { missing.append("First Responder Name") }

        return DD1380ReadinessResult(
            hasPatientIdentity: hasIdentity,
            hasDateTime: hasDateTime,
            hasClinicalContent: hasClinical,
            hasSectionCVital: hasSectionC,
            hasFirstResponder: hasResponder,
            criticalMissing: missing
        )
    }

    private static func hasAnyTreatment(_ t: DD1380TreatmentFlags) -> Bool {
        t.tqExtremity || t.tqJunctional || t.tqTruncal
            || t.dressingHemostatic || t.dressingPressure || t.dressingOther
            || t.airwayIntact || t.airwayNPA || t.airwayCRIC || t.airwayETTube || t.airwaySGA
            || t.breathingO2 || t.breathingNeedleD || t.breathingChestTube || t.breathingChestSeal
    }

    private static func hasAnyOther(_ o: DD1380OtherTreatmentFlags) -> Bool {
        o.combatPillPack || o.eyeShieldRight || o.eyeShieldLeft
            || o.splint || o.hypothermiaPrevention
    }
}
