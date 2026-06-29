import Foundation
import TCCCDomain

/// Deterministically maps structured `PatientState` + app metadata onto the
/// DD Form 1380 field model. Pure: no app-target import, no `Date()` inside
/// (timestamps come from the input), no LLM output, no narrative/ZMIST prose.
/// Unknown fields stay blank; nothing is inferred that the structured state
/// does not already represent. Same input → identical `DD1380CardData`.
public enum DD1380Mapper {

    public static func map(_ input: DD1380MapperInput) -> DD1380CardData {
        var card = DD1380CardData()
        let p = input.patient

        // §A — front header
        card.nameLastFirst = input.casualtyName
        card.last4 = input.casualtyLast4
        card.sex = input.casualtySex
        card.service = input.casualtyService
        card.unit = input.casualtyUnit
        card.allergies = input.casualtyAllergies
        card.battleRosterNumber = battleRoster(name: input.casualtyName, last4: input.casualtyLast4)
        card.evacCategory = evac(p.classification)
        card.dateDDMMMYY = dateFormatter.string(from: input.encounterStart).uppercased()
        card.timeHHMM = timeFormatter.string(from: input.encounterStart) + "Z"

        // §B — mechanism / tourniquets (injury marks → Notes, never invented coords)
        card.mechanisms = mechanism(from: p.mechanismOfInjury)
        card.tourniquets = tourniquets(from: p)

        // §C — up to four timestamped vital columns (pre-converted by the caller)
        card.sectionCReadings = Array(input.sectionCReadings.prefix(4))

        // §E / §F — treatments + meds
        card.treatments = treatments(from: p)
        card.medications = medications(from: p)
        card.otherTreatments = otherTreatments(from: p)

        // §G — notes (structured leftovers only)
        card.notes = notes(from: p, mechanism: card.mechanisms)

        // §H — first responder (operator identity)
        card.firstResponderName = input.operatorName
        card.firstResponderLast4 = input.operatorLast4

        return card
    }

    // MARK: - §A helpers

    static func evac(_ classification: Classification?) -> DD1380EvacCategory? {
        switch classification {
        case .urgent, .urgentSurgical: return .urgent
        case .priority:                return .priority
        case .routine:                 return .routine
        case .expectant, .none:        return nil   // no DD1380 box for Expectant
        }
    }

    /// Battle Roster # per the field's own definition: first initial + last
    /// initial (name is "Last, First") + last-4. Composing existing data into
    /// the required format — not inventing. Blank if name or last-4 is absent.
    static func battleRoster(name: String, last4: String) -> String {
        let digits = String(last4.filter(\.isNumber))
        guard digits.count == 4 else { return "" }
        let parts = name.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2,
              let lastInitial = parts[0].first(where: \.isLetter),
              let firstInitial = parts[1].first(where: \.isLetter) else { return "" }
        return "\(firstInitial)\(lastInitial)\(digits)".uppercased()
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd-MMM-yy"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HHmm"
        return f
    }()

    // MARK: - §B mechanism

    static func mechanism(from moi: String?) -> DD1380MechanismFlags {
        var flags = DD1380MechanismFlags()
        guard let original = moi?.trimmingCharacters(in: .whitespacesAndNewlines),
              !original.isEmpty else { return flags }
        let raw = original.lowercased()
        func has(_ keywords: [String]) -> Bool { keywords.contains { raw.contains($0) } }

        if has(["gsw", "gunshot", "gun shot", "gun-shot"]) { flags.gsw = true }
        if has(["ied", "improvised explosive"]) { flags.ied = true }
        if has(["rpg", "rocket propelled", "rocket-propelled"]) { flags.rpg = true }
        if has(["grenade"]) { flags.grenade = true }
        if has(["landmine", "land mine"]) { flags.landmine = true }
        if has(["artillery", "mortar"]) { flags.artillery = true }
        if has(["mvc", "motor vehicle", "rollover", "vehicle crash", "vehicle accident"]) { flags.mvc = true }
        if has(["burn", "thermal", "scald"]) { flags.burn = true }
        if has(["fall", "fell"]) { flags.fall = true }
        if has(["blunt", "crush"]) { flags.blunt = true }

        // No recognized device/cause box → Other, preserving the verbatim text.
        // Generic "blast"/"penetrating"/"shrapnel" land here rather than being
        // guessed onto a specific device box.
        if !flags.anyChecked {
            flags.other = true
            flags.otherText = original
        }
        return flags
    }

    // MARK: - §B tourniquets

    static func tourniquets(from p: PatientState) -> [DD1380TourniquetEntry] {
        let limb = limb(from: p.march.hemorrhageLocation)
        let locationText = limb == nil ? p.march.hemorrhageLocation?
            .trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let tqInterventions = p.interventions.filter { $0.kind == .tourniquet }

        if tqInterventions.isEmpty {
            // Fall back to the MARCH hemorrhage-intervention string only if it
            // clearly names a tourniquet — no time available then.
            if let hi = p.march.hemorrhageIntervention?.lowercased(),
               hi.contains("tourniquet") || hi.contains(" tq") || hi.hasPrefix("tq") {
                return [DD1380TourniquetEntry(limb: limb, type: nil, timeHHMM: nil,
                                              locationText: locationText)]
            }
            return []
        }

        return tqInterventions.map { iv in
            DD1380TourniquetEntry(
                limb: limb,
                type: nil,                       // never inferred
                timeHHMM: timeFormatter.string(from: iv.timestamp),
                locationText: locationText
            )
        }
    }

    static func limb(from location: String?) -> DD1380Limb? {
        guard let loc = location?.lowercased() else { return nil }
        let isLeft = loc.contains("left")
        let isRight = loc.contains("right")
        let isArm = loc.contains("arm") || loc.contains("forearm")
            || loc.contains("hand") || loc.contains("brachial") || loc.contains("shoulder")
        let isLeg = loc.contains("leg") || loc.contains("thigh") || loc.contains("femur")
            || loc.contains("calf") || loc.contains("knee") || loc.contains("groin")
        if isLeft && isArm { return .leftArm }
        if isRight && isArm { return .rightArm }
        if isLeft && isLeg { return .leftLeg }
        if isRight && isLeg { return .rightLeg }
        return nil
    }

    // MARK: - §E treatments

    static func treatments(from p: PatientState) -> DD1380TreatmentFlags {
        var t = DD1380TreatmentFlags()
        let kinds = Set(p.interventions.map(\.kind))

        // C — hemorrhage control
        if kinds.contains(.tourniquet) { t.tqExtremity = true }
        if p.interventions.contains(where: {
            $0.kind == .tourniquet && $0.description.lowercased().contains("junctional")
        }) { t.tqJunctional = true; t.tqExtremity = false }

        if kinds.contains(.pressureDressing) { t.dressingPressure = true }
        if kinds.contains(.dressing) || kinds.contains(.woundCare) {
            let hemostatic = p.interventions.contains {
                ($0.kind == .dressing || $0.kind == .woundCare) && isHemostatic($0.description)
            }
            if hemostatic { t.dressingHemostatic = true } else { t.dressingOther = true }
        }

        // A — airway
        if kinds.contains(.npa) { t.airwayNPA = true }
        if kinds.contains(.surgicalAirway) { t.airwayCRIC = true }
        if let ai = p.march.airwayIntervention?.lowercased() {
            if ai.contains("npa") || ai.contains("nasopharyngeal") { t.airwayNPA = true }
            if ai.contains("cric") { t.airwayCRIC = true }
            if ai.contains("et tube") || ai.contains("et-tube") || ai.contains("intubat") { t.airwayETTube = true }
            if ai.contains("sga") || ai.contains("supraglottic") || ai.contains("i-gel") || ai.contains("igel") { t.airwaySGA = true }
        }
        let hasAirwayDevice = t.airwayNPA || t.airwayCRIC || t.airwayETTube || t.airwaySGA
        if !hasAirwayDevice, p.march.airwayStatus?.lowercased().contains("patent") == true {
            t.airwayIntact = true
        }

        // B — breathing
        if kinds.contains(.chestSeal) { t.breathingChestSeal = true }
        if kinds.contains(.needleDecompression) { t.breathingNeedleD = true }
        if let ri = p.march.respirationIntervention?.lowercased() {
            if ri.contains("chest seal") || ri.contains("chest-seal") { t.breathingChestSeal = true }
            if ri.contains("needle") || ri.contains("decompress") || ri.contains("ndc") { t.breathingNeedleD = true }
            if ri.contains("chest tube") || ri.contains("thoracostomy") { t.breathingChestTube = true }
            if ri.contains("oxygen") || ri.contains(" o2") || ri.hasPrefix("o2") { t.breathingO2 = true }
        }
        return t
    }

    static func isHemostatic(_ description: String) -> Bool {
        let d = description.lowercased()
        return d.contains("hemostatic") || d.contains("combat gauze") || d.contains("celox")
            || d.contains("chitogauze") || d.contains("chito") || d.contains("xstat")
            || d.contains("quikclot") || d.contains("quick clot")
    }

    // MARK: - §F meds + other

    static func medications(from p: PatientState) -> [DD1380MedicationEntry] {
        var meds: [DD1380MedicationEntry] = []
        for iv in p.interventions {
            let category: DD1380MedCategory
            switch iv.kind {
            case .antibiotic:     category = .antibiotic
            case .painManagement: category = .analgesic
            case .medication:     category = .other
            default:              continue
            }
            let name = iv.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            // dose/route are not structured in the domain → left blank, never invented.
            meds.append(DD1380MedicationEntry(
                category: category, name: name, dose: nil, route: nil,
                timeHHMM: timeFormatter.string(from: iv.timestamp)
            ))
        }
        return meds
    }

    static func otherTreatments(from p: PatientState) -> DD1380OtherTreatmentFlags {
        var o = DD1380OtherTreatmentFlags()
        let kinds = Set(p.interventions.map(\.kind))

        if kinds.contains(.splint) || isNonEmpty(p.paws.splinting) { o.splint = true }

        if kinds.contains(.hypothermiaPrevention) || isNonEmpty(p.march.hypothermiaPrevention) {
            o.hypothermiaPrevention = true
            o.hypothermiaType = p.march.hypothermiaPrevention?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if let pain = p.paws.pain?.lowercased(),
           pain.contains("pill pack") || pain.contains("cwmp") || pain.contains("combat pill") {
            o.combatPillPack = true
        }
        return o
    }

    // MARK: - §G notes

    static func notes(from p: PatientState, mechanism: DD1380MechanismFlags) -> String {
        // Deterministic, structured leftovers only — no LLM prose, no GPS/MGRS.
        var lines: [String] = []
        appendIf(&lines, "Hemorrhage", p.march.hemorrhageLocation)
        if !p.injuries.isEmpty {
            lines.append("Injuries: \(p.injuries.joined(separator: ", "))")
        }
        if mechanism.other, !mechanism.otherText.isEmpty {
            lines.append("MOI: \(mechanism.otherText)")
        }
        appendIf(&lines, "Breath sounds", p.march.breathSounds)
        appendIf(&lines, "Skin", p.march.skinSigns)
        appendIf(&lines, "Pulse", p.march.pulseStatus)
        appendIf(&lines, "Pupils", p.march.pupilResponse)
        appendIf(&lines, "Wounds", p.paws.wounds)
        appendIf(&lines, "Splint", p.paws.splinting)
        appendIf(&lines, "Antibiotics", p.paws.antibiotics)
        appendIf(&lines, "Pain mgmt", p.paws.pain)
        appendIf(&lines, "Hypothermia", p.march.hypothermiaPrevention)
        return lines.joined(separator: "\n")
    }

    private static func appendIf(_ lines: inout [String], _ label: String, _ value: String?) {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
        lines.append("\(label): \(v)")
    }

    private static func isNonEmpty(_ s: String?) -> Bool {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !s.isEmpty
    }

    // MARK: - Shared conversion helper (used by the app's Section C conversion)

    /// Normalize an AVPU consciousness string ("Alert"/"Voice"/"Pain"/
    /// "Unresponsive", or a bare letter) to its DD1380 letter.
    public static func avpuLetter(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !t.isEmpty else { return nil }
        if t.hasPrefix("a") || t.contains("alert") { return "A" }
        if t.hasPrefix("v") || t.contains("voice") || t.contains("verbal") { return "V" }
        if t.hasPrefix("p") || t.contains("pain") { return "P" }
        if t.hasPrefix("u") || t.contains("unrespons") { return "U" }
        return nil
    }
}
