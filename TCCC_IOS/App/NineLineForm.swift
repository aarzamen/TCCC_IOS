import Foundation
import TCCCDomain

struct NineLineEntry: Identifiable, Equatable {
    /// Line-1 source-aware statuses:
    /// - `.ok`      — GPS fix with a valid full-precision MGRS; ready.
    /// - `.pending` — no usable GPS fix (or MGRS conversion failed);
    ///   operator must capture a GPS fix before transmit.
    enum Status: Equatable { case ok, warn, crit, auto, pending }

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
        callsign: String = "",
        frequency: String = "",
        operatorValues: [Int: String] = [:]
    ) -> NineLineForm {
        let urgent = patients.filter { $0.classification == .urgent }.count
        let urgentSurg = patients.filter { $0.classification == .urgentSurgical }.count
        let priority = patients.filter { $0.classification == .priority }.count
        let routine = patients.filter { $0.classification == .routine }.count


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
            value: frequency.isEmpty || callsign.isEmpty ? "—" : "\(frequency) · \(callsign)",
            icon: "antenna.radiowaves.left.and.right",
            status: .ok,
            isAuto: false
        ))

        // Line 3 — Patients by precedence
        let line3Value = patients.contains { $0.classification == nil } ? "—" : formattedPrecedence(urgent: urgent, urgentSurg: urgentSurg, priority: priority, routine: routine)
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
        entries.append(.init(
            number: 4,
            label: "SPECIAL EQUIPMENT",
            value: "—",
            icon: "lungs",
            status: .ok,
            isAuto: false
        ))

        // Line 5 — Patients by type (litter / ambulatory)
        entries.append(.init(
            number: 5,
            label: "PATIENTS BY TYPE",
            value: "—",
            icon: "person.fill",
            status: .ok,
            isAuto: false
        ))

        // Line 6 — Security (default per Python — no engine signal)
        entries.append(.init(
            number: 6,
            label: "SECURITY (WAR)",
            value: "—",
            icon: "exclamationmark.triangle",
            status: .warn,
            isAuto: false
        ))

        // Line 7 — Marking
        entries.append(.init(
            number: 7,
            label: "MARKING METHOD",
            value: "—",
            icon: "smoke.fill",
            status: .ok,
            isAuto: false
        ))

        // Line 8 — Patient nationality
        entries.append(.init(
            number: 8,
            label: "PT NATIONALITY",
            value: "—",
            icon: "checkmark.circle",
            status: .ok,
            isAuto: false
        ))

        // Line 9 — CBRN
        entries.append(.init(
            number: 9,
            label: "CBRN CONTAMINATION",
            value: "—",
            icon: "shield.lefthalf.filled",
            status: .ok,
            isAuto: false
        ))

        // Operational lines require actual operator input. No assumed nationality,
        // equipment, security, marking, contamination, or transport posture.
        entries = entries.map { entry in
            guard entry.number != 1 else { return entry }
            let supplied = operatorValues[entry.number]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = supplied.map { $0.isEmpty ? "—" : $0 } ?? entry.value
            let unknown = ["", "—", "-", "?", "unknown", "unverified", "pending", "tbd", "not assessed", "not entered"]
                .contains(value.lowercased())
            return NineLineEntry(number: entry.number, label: entry.label, value: value,
                icon: entry.icon, status: unknown ? .pending : .ok, isAuto: false)
        }
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

}
