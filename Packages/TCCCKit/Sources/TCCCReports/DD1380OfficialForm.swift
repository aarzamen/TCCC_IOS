import Foundation

// MARK: - Official DD Form 1380 field values
//
// Maps a `DD1380CardData` onto the fields of the official DD Form 1380
// (JUN 2014) template bundled with the app. Field names are the honest flat
// names written by `tools/prepare_dd1380_template.py` (the official form's own
// names are wrong in places); `DD1380_JUN2014_fields.json` lists them.
// Pure and deterministic: nothing is inferred, blank stays blank, and nothing
// is dropped. Entries that have no row left, and notes that do not fit the
// Notes box, are carried forward instead.

/// Values to write into the official form. `continuationNotes` holds the part
/// of Notes that does not fit the box; the app prints it on an extra page.
public struct DD1380FormValues: Sendable, Equatable {
    public var text: [String: String] = [:]
    public var checked: Set<String> = []
    public var continuationNotes: String?

    public init() {}
}

public enum DD1380OfficialForm {
    public static let edition = "DD Form 1380, JUN 2014"
    /// Bundle resource name (`.pdf`) of the template, and of its `_fields.json` manifest.
    public static let templateResource = "DD1380_JUN2014_template"
    public static let manifestResource = "DD1380_JUN2014_fields"
    public static let continuationMarker = "(continued on next page)"

    /// Notes box capacity at 7 pt (356 × 90 pt box), checked against a render.
    public static let notesCharsPerLine = 95
    public static let notesMaxLines = 11

    static let analgesicRows = 3
    static let antibioticRows = 2
    static let otherMedRows = 2
    static let fluidRows = 2
    static let bloodRows = 2
    static let vitalsColumns = 4

    public static func values(for card: DD1380CardData) -> DD1380FormValues {
        var v = DD1380FormValues()
        var overflow: [String] = []

        func put(_ field: String, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            v.text[field] = value
        }
        func check(_ field: String, _ on: Bool) { if on { v.checked.insert(field) } }

        // §A — header (BR# and EVAC are printed on both pages)
        put("br_number", card.battleRosterNumber)
        put("br_number_back", card.battleRosterNumber)
        if let evac = card.evacCategory {
            let field: String
            switch evac {
            case .urgent: field = "evac_urgent"
            case .priority: field = "evac_priority"
            case .routine: field = "evac_routine"
            }
            check(field, true)
            check(field + "_back", true)
        }
        put("name", card.nameLastFirst)
        put("last4", card.last4)
        check("sex_m", card.sex == .male)
        check("sex_f", card.sex == .female)
        put("date", card.dateDDMMMYY)
        put("time", card.timeHHMM)
        put("service", card.service)
        put("unit", card.unit)
        put("allergies", card.allergies)

        // §B — mechanism of injury
        let m = card.mechanisms
        check("moi_artillery", m.artillery)
        check("moi_blunt", m.blunt)
        check("moi_burn", m.burn)
        check("moi_fall", m.fall)
        check("moi_grenade", m.grenade)
        check("moi_gsw", m.gsw)
        check("moi_ied", m.ied)
        check("moi_landmine", m.landmine)
        check("moi_mvc", m.mvc)
        check("moi_rpg", m.rpg)
        check("moi_other", m.other)
        if m.other { put("moi_other_text", m.otherText) }

        // §B — one tourniquet box per limb; the rest go to Notes
        var usedLimbs: Set<String> = []
        for tq in card.tourniquets {
            if let limb = tq.limb, !usedLimbs.contains(limb.rawValue) {
                usedLimbs.insert(limb.rawValue)
                let prefix = limbField(limb)
                put(prefix + "_type", tq.type)
                put(prefix + "_time", tq.timeHHMM)
            } else {
                let place = tq.limb?.rawValue ?? tq.locationText ?? "location unknown"
                overflow.append(line("TQ", [place, tq.type, tq.timeHHMM]))
            }
        }

        // §C — signs & symptoms, four columns; later readings go to Notes
        for (index, reading) in card.sectionCReadings.enumerated() {
            guard index < vitalsColumns else {
                overflow.append(vitalsLine(reading))
                continue
            }
            let col = "vitals\(index + 1)"
            put(col + "_time", reading.timeHHMM)
            put(col + "_pulse", reading.pulse)
            let bp = splitBloodPressure(reading.bloodPressure)
            put(col + "_sbp", bp.systolic)
            put(col + "_dbp", bp.diastolic)
            put(col + "_rr", reading.respiratoryRate)
            put(col + "_spo2", reading.spo2)
            put(col + "_avpu", reading.avpu)
            put(col + "_pain", reading.pain)
        }

        // §E — treatments
        let t = card.treatments
        check("tq_extremity", t.tqExtremity)
        check("tq_junctional", t.tqJunctional)
        check("tq_truncal", t.tqTruncal)
        put("tq_type_text", t.tqTypeText)
        check("dressing_hemostatic", t.dressingHemostatic)
        check("dressing_pressure", t.dressingPressure)
        check("dressing_other", t.dressingOther)
        put("dressing_type_text", t.dressingTypeText)
        check("airway_intact", t.airwayIntact)
        check("airway_npa", t.airwayNPA)
        check("airway_cric", t.airwayCRIC)
        check("airway_et_tube", t.airwayETTube)
        check("airway_sga", t.airwaySGA)
        put("airway_type_text", t.airwayTypeText)
        check("breathing_o2", t.breathingO2)
        check("breathing_needle_d", t.breathingNeedleD)
        check("breathing_chest_tube", t.breathingChestTube)
        check("breathing_chest_seal", t.breathingChestSeal)
        put("breathing_type_text", t.breathingTypeText)

        // §E — fluid and blood product rows
        func fillFluids(_ entries: [DD1380FluidEntry], prefix: String, rows: Int, label: String) {
            for (index, entry) in entries.enumerated() {
                if index < rows {
                    let row = "\(prefix)\(index + 1)"
                    put(row + "_name", entry.name)
                    put(row + "_volume", entry.volume)
                    put(row + "_route", entry.route)
                    put(row + "_time", entry.timeHHMM)
                } else {
                    overflow.append(line(label, [entry.name, entry.volume, entry.route, entry.timeHHMM]))
                }
            }
        }

        // §F — medication rows by category
        func fillMeds(_ category: DD1380MedCategory, prefix: String, rows: Int, label: String) {
            let entries = card.medications.filter { $0.category == category }
            for (index, entry) in entries.enumerated() {
                if index < rows {
                    let row = "\(prefix)\(index + 1)"
                    put(row + "_name", entry.name)
                    put(row + "_dose", entry.dose)
                    put(row + "_route", entry.route)
                    put(row + "_time", entry.timeHHMM)
                } else {
                    overflow.append(line(label, [entry.name, entry.dose, entry.route, entry.timeHHMM]))
                }
            }
        }
        fillMeds(.analgesic, prefix: "analgesic", rows: analgesicRows, label: "Analgesic")
        fillMeds(.antibiotic, prefix: "antibiotic", rows: antibioticRows, label: "Antibiotic")
        fillMeds(.other, prefix: "othermed", rows: otherMedRows, label: "Medication")
        fillFluids(card.fluids, prefix: "fluid", rows: fluidRows, label: "Fluid")
        fillFluids(card.bloodProducts, prefix: "blood", rows: bloodRows, label: "Blood product")

        // §F — OTHER row
        let o = card.otherTreatments
        check("other_pill_pack", o.combatPillPack)
        check("other_eye_shield", o.eyeShieldRight || o.eyeShieldLeft)
        check("other_eye_shield_r", o.eyeShieldRight)
        check("other_eye_shield_l", o.eyeShieldLeft)
        check("other_splint", o.splint)
        check("other_hypothermia", o.hypothermiaPrevention)
        if o.hypothermiaPrevention { put("other_hypothermia_type", o.hypothermiaType) }

        // §G — notes: the card's own notes first, then everything without a row
        let cardNotes = card.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let allNotes = ([cardNotes] + overflow).filter { !$0.isEmpty }.joined(separator: "\n")
        let split = splitNotes(allNotes, charsPerLine: notesCharsPerLine, maxLines: notesMaxLines)
        put("notes", split.onForm)
        v.continuationNotes = split.overflow

        // §H — first responder
        put("responder_name", card.firstResponderName)
        put("responder_last4", card.firstResponderLast4)
        return v
    }

    /// Splits notes so the part on the form fits `maxLines` wrapped lines,
    /// ending in `continuationMarker` when anything is carried over. Cuts at a
    /// line break where possible, else at the last space; nothing is lost.
    static func splitNotes(_ notes: String, charsPerLine: Int, maxLines: Int) -> (onForm: String, overflow: String?) {
        let lines = notes.components(separatedBy: "\n")
        func wrapped(_ line: String) -> Int { max(1, (line.count + charsPerLine - 1) / charsPerLine) }
        if notes.isEmpty || lines.map(wrapped).reduce(0, +) <= maxLines { return (notes, nil) }

        let budget = maxLines - 1   // the last line holds the marker
        var kept: [String] = []
        var rest: [String] = []
        var used = 0
        for (index, line) in lines.enumerated() {
            if !rest.isEmpty || used >= budget {
                rest.append(line)
                continue
            }
            let need = wrapped(line)
            if used + need <= budget {
                kept.append(line)
                used += need
                continue
            }
            // Partial line: keep what fits, cut at the last space.
            let room = (budget - used) * charsPerLine
            let head = line.prefix(room)
            if let space = head.lastIndex(of: " ") {
                kept.append(String(line[..<space]))
                rest.append(String(line[line.index(after: space)...]))
            } else {
                kept.append(String(head))
                rest.append(String(line.dropFirst(room)))
            }
            used = budget
            rest.append(contentsOf: lines[(index + 1)...])
            break
        }
        return (kept.joined(separator: "\n") + "\n" + continuationMarker, rest.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private static func limbField(_ limb: DD1380Limb) -> String {
        switch limb {
        case .rightArm: return "tq_r_arm"
        case .leftArm: return "tq_l_arm"
        case .rightLeg: return "tq_r_leg"
        case .leftLeg: return "tq_l_leg"
        }
    }

    /// "120/80" → ("120", "80"); anything else stays whole in the systolic box.
    static func splitBloodPressure(_ value: String?) -> (systolic: String?, diastolic: String?) {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return (nil, nil) }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { return (parts[0], parts[1]) }
        return (raw, nil)
    }

    private static func line(_ label: String, _ parts: [String?]) -> String {
        let body = parts.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return "\(label): " + body.joined(separator: " ")
    }

    private static func vitalsLine(_ r: DD1380SectionCReading) -> String {
        let parts: [(String, String?)] = [("P", r.pulse), ("BP", r.bloodPressure), ("RR", r.respiratoryRate),
                                          ("SpO2", r.spo2), ("AVPU", r.avpu), ("Pain", r.pain)]
        let body = parts.compactMap { label, value in value.map { "\(label) \($0)" } }
        return "Vitals \(r.timeHHMM): " + body.joined(separator: ", ")
    }
}
