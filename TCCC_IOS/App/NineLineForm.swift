import Foundation
import TCCCDomain

struct NineLineEntry: Identifiable {
    /// Line-1 source-aware statuses:
    /// - `.ok`      — GPS fix with a valid full-precision MGRS; ready.
    /// - `.pending` — no usable GPS fix (or MGRS conversion failed);
    ///   operator must capture a GPS fix before transmit.
    enum Status { case ok, warn, crit, auto, pending }

    let number: Int
    let label: String
    let value: String
    let icon: String
    let status: Status
    let isAuto: Bool

    var id: Int { number }

    var countsTowardCompletion: Bool {
        value != "—" && status != .pending
    }

    var isVerifiedForTransmit: Bool {
        countsTowardCompletion
    }
}

struct NineLineForm {
    let entries: [NineLineEntry]
    let completedCount: Int
    let totalCount: Int

    var isReadyForTransmit: Bool {
        entries.count == totalCount && entries.allSatisfy(\.isVerifiedForTransmit)
    }

    var blockingTransmitEntry: NineLineEntry? {
        entries.first { !$0.isVerifiedForTransmit }
    }

    static func derive(
        from patients: [PatientState],
        locationFix: AppState.LocationFix,
        callsign: String = "MEDEVAC",
        frequency: String = "38.65 FM"
    ) -> NineLineForm {
        let urgent = patients.filter { $0.classification == .urgent || $0.classification == nil }.count
        let urgentSurg = patients.filter { $0.classification == .urgentSurgical }.count
        let priority = patients.filter { $0.classification == .priority }.count
        let routine = patients.filter { $0.classification == .routine }.count

        let (litter, ambulatory) = litterCount(patients)

        var entries: [NineLineEntry] = []

        // Line 1 — Location. Production: GPS only, full-precision MGRS, no
        // fabrication and no decimal-degrees fallback.
        //   • no usable GPS fix            → UNVERIFIED, pending, not ready
        //   • GPS fix + MGRS encodes       → 5+5 MGRS, ok, ready (badge GPS)
        //   • GPS fix but MGRS nil (polar) → MGRS UNAVAILABLE, pending, not ready
        let line1Value: String
        let line1Status: NineLineEntry.Status
        let line1IsAuto: Bool
        if locationFix.isUsable,
           let lat = locationFix.latitude,
           let lon = locationFix.longitude {
            if let mgrs = MGRS.formatted(latitude: lat, longitude: lon) {
                line1Value = mgrs
                line1Status = .ok
                line1IsAuto = true          // GPS-derived → badge renders GPS
            } else {
                line1Value = "MGRS UNAVAILABLE"
                line1Status = .pending
                line1IsAuto = false
            }
        } else {
            line1Value = "UNVERIFIED — use GPS fix"
            line1Status = .pending
            line1IsAuto = false
        }
        entries.append(.init(
            number: 1,
            label: "LOCATION",
            value: line1Value,
            icon: "mappin.and.ellipse",
            status: line1Status,
            isAuto: line1IsAuto
        ))

        // Line 2 — Frequency / Callsign
        entries.append(.init(
            number: 2,
            label: "FREQ / CALL",
            value: "\(frequency) · \(callsign)",
            icon: "antenna.radiowaves.left.and.right",
            status: .ok,
            isAuto: false
        ))

        // Line 3 — Patients by precedence
        let line3Value = formattedPrecedence(urgent: urgent, urgentSurg: urgentSurg, priority: priority, routine: routine)
        let line3Status: NineLineEntry.Status = (urgent + urgentSurg) > 0 ? .crit : (priority > 0 ? .warn : .ok)
        entries.append(.init(
            number: 3,
            label: "PATIENTS BY PRECEDENCE",
            value: line3Value,
            icon: "person.fill",
            status: line3Status,
            isAuto: false
        ))

        // Line 4 — Special equipment
        let line4 = specialEquipment(patients)
        entries.append(.init(
            number: 4,
            label: "SPECIAL EQUIPMENT",
            value: line4,
            icon: "lungs",
            status: .ok,
            isAuto: false
        ))

        // Line 5 — Patients by type (litter / ambulatory)
        let total = litter + ambulatory
        let line5: String
        if litter > 0 && ambulatory > 0 {
            line5 = "L\(litter)  ·  A\(ambulatory)  ·  \(total) total"
        } else if litter > 0 {
            line5 = "L\(litter)  ·  \(litter) litter"
        } else if ambulatory > 0 {
            line5 = "A\(ambulatory)  ·  \(ambulatory) ambulatory"
        } else {
            line5 = "—"
        }
        entries.append(.init(
            number: 5,
            label: "PATIENTS BY TYPE",
            value: line5,
            icon: "person.fill",
            status: .ok,
            isAuto: false
        ))

        // Line 6 — Security (default per Python — no engine signal)
        entries.append(.init(
            number: 6,
            label: "SECURITY (WAR)",
            value: "P · POSSIBLE ENEMY",
            icon: "exclamationmark.triangle",
            status: .warn,
            isAuto: false
        ))

        // Line 7 — Marking
        entries.append(.init(
            number: 7,
            label: "MARKING METHOD",
            value: "C · SMOKE — VS-17 BACKUP",
            icon: "smoke.fill",
            status: .ok,
            isAuto: false
        ))

        // Line 8 — Patient nationality
        entries.append(.init(
            number: 8,
            label: "PT NATIONALITY",
            value: "A · US MIL",
            icon: "checkmark.circle",
            status: .ok,
            isAuto: false
        ))

        // Line 9 — CBRN
        entries.append(.init(
            number: 9,
            label: "CBRN CONTAMINATION",
            value: "N · NONE",
            icon: "shield.lefthalf.filled",
            status: .ok,
            isAuto: false
        ))

        let completed = entries.filter(\.countsTowardCompletion).count
        return NineLineForm(entries: entries, completedCount: completed, totalCount: 9)
    }

    // MARK: - Helpers

    private static func formattedPrecedence(urgent: Int, urgentSurg: Int, priority: Int, routine: Int) -> String {
        var parts: [String] = []
        if urgent > 0 { parts.append("\(urgent)× URGENT (A)") }
        if urgentSurg > 0 { parts.append("\(urgentSurg)× URG SURG (A)") }
        if priority > 0 { parts.append("\(priority)× PRIORITY (B)") }
        if routine > 0 { parts.append("\(routine)× ROUTINE (C)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// Litter / ambulatory split mirroring the litter rules from
    /// `reports.py:_calculate_litter_ambulatory`. Lower-extremity hemorrhage,
    /// reduced consciousness, or `urgent` classification all force litter.
    private static func litterCount(_ patients: [PatientState]) -> (litter: Int, ambulatory: Int) {
        var litter = 0
        var ambulatory = 0
        for patient in patients {
            if patientNeedsLitter(patient) { litter += 1 } else { ambulatory += 1 }
        }
        return (litter, ambulatory)
    }

    private static func patientNeedsLitter(_ patient: PatientState) -> Bool {
        if patient.classification == .urgent || patient.classification == .urgentSurgical {
            return true
        }
        if let cons = patient.march.consciousness?.lowercased(),
           cons.contains("voice") || cons.contains("pain") || cons.contains("unresponsive") {
            return true
        }
        if let loc = patient.march.hemorrhageLocation?.lowercased(),
           loc.contains("thigh") || loc.contains("leg") || loc.contains("femur") {
            return true
        }
        return false
    }

    private static func specialEquipment(_ patients: [PatientState]) -> String {
        var equipment: [String] = []
        for patient in patients {
            if let air = patient.march.airwayIntervention?.lowercased(),
               air.contains("cric") || air.contains("vent") {
                equipment.append("VENTILATOR")
            }
            if let resp = patient.march.respirationIntervention?.lowercased(),
               resp.contains("vent") || resp.contains("intubat") {
                equipment.append("VENTILATOR")
            }
        }
        let unique = Set(equipment)
        if unique.isEmpty { return "A · NONE" }
        if unique.contains("VENTILATOR") { return "B · VENTILATOR" }
        return "A · NONE"
    }
}
