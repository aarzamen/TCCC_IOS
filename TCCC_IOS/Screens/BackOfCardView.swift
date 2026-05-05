import SwiftUI
import TCCCDomain

/// DD 1380 back-of-card flow — sections D, E, F, G, H.
///
/// Renders all six rubric sections with best-effort population from the
/// current PatientState. Empty fields show "—" placeholders. This is the
/// 2026 sprint Phase 4 Task 4.3 deliverable: scaffold every DD 1380 field
/// in the data model so the medic can confirm or override before handoff.
///
/// Reference: reference/rubric/extracted/dd1380_field_inventory.json
/// fields with section_identifier in {D, E, F, G, H}.
///
/// **Editing is read-only for now.** Future work: tap-to-edit each field;
/// persist edits back into the patient record.
struct BackOfCardView: View {
    let state: AppState
    @Environment(\.palette) private var palette

    private var patient: PatientState? { state.primaryPatient }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionD
                sectionE
                sectionF
                sectionG
                sectionH
            }
            .padding(Layout.outerPadding)
        }
    }

    // MARK: - Section D — Battle Roster + EVAC repeat

    private var sectionD: some View {
        sectionPanel("D · Header (repeat)") {
            VStack(alignment: .leading, spacing: 6) {
                fieldRow("Battle Roster", value: state.casualtyServiceNumberMasked)
                fieldRow("EVAC", value: evacLabel)
            }
        }
    }

    private var evacLabel: String {
        guard let cls = patient?.classification else { return "—" }
        switch cls {
        case .urgent, .urgentSurgical: return "Urgent"
        case .priority:                return "Priority"
        case .routine:                 return "Routine"
        case .expectant:               return "Expectant"
        }
    }

    // MARK: - Section E — Treatments

    private var sectionE: some View {
        sectionPanel("E · Treatments") {
            VStack(alignment: .leading, spacing: 8) {
                subhead("C — Hemorrhage Control")
                fieldRow("TQ", value: tqCategoryLabel)
                fieldRow("TQ Type", value: tqTypeLabel)
                fieldRow("Dressing", value: dressingCategoryLabel)
                fieldRow("Dressing Type", value: dressingTypeLabel)

                Divider().background(palette.line)
                subhead("A — Airway")
                fieldRow("A:", value: airwayCategoryLabel)
                fieldRow("Treatment Type", value: airwayTypeLabel)

                Divider().background(palette.line)
                subhead("B — Breathing")
                fieldRow("B:", value: breathingCategoryLabel)
                fieldRow("Treatment Type", value: breathingTypeLabel)

                Divider().background(palette.line)
                subhead("C — Fluids / Blood Products")
                fieldRow("Fluid", value: "—")
                fieldRow("Blood Product", value: "—")
            }
        }
    }

    private var tqCategoryLabel: String {
        guard let intervention = patient?.march.hemorrhageIntervention else { return "—" }
        return intervention.lowercased().contains("tourniquet") ? "Extremity" : "—"
    }
    private var tqTypeLabel: String {
        // The 2026 vocabulary doesn't yet capture the brand (CAT, SOFTT-W);
        // medic completes this on handoff.
        guard let intervention = patient?.march.hemorrhageIntervention,
              intervention.lowercased().contains("tourniquet") else { return "—" }
        return "(specify on card)"
    }
    private var dressingCategoryLabel: String {
        guard let intervention = patient?.march.hemorrhageIntervention?.lowercased() else { return "—" }
        if intervention.contains("hemostatic") || intervention.contains("combat gauze") {
            return "Hemostatic"
        }
        if intervention.contains("pressure dressing") { return "Pressure" }
        return "—"
    }
    private var dressingTypeLabel: String {
        guard let intervention = patient?.march.hemorrhageIntervention,
              dressingCategoryLabel != "—" else { return "—" }
        return intervention
    }
    private var airwayCategoryLabel: String {
        guard let intervention = patient?.march.airwayIntervention?.lowercased() else {
            // No intervention — patent airway implies "Intact" per DD 1380
            // §E A: column.
            return patient?.march.airwayStatus == "patent" ? "Intact" : "—"
        }
        if intervention.contains("npa") { return "NPA" }
        if intervention.contains("cric") { return "CRIC" }
        return "—"
    }
    private var airwayTypeLabel: String {
        patient?.march.airwayIntervention ?? "—"
    }
    private var breathingCategoryLabel: String {
        guard let intervention = patient?.march.respirationIntervention?.lowercased() else { return "—" }
        if intervention.contains("chest seal") { return "Chest-Seal" }
        if intervention.contains("needle decompression") { return "Needle-D" }
        return "—"
    }
    private var breathingTypeLabel: String {
        patient?.march.respirationIntervention ?? "—"
    }

    // MARK: - Section F — MEDS + OTHER row

    private var sectionF: some View {
        sectionPanel("F · MEDS + Other") {
            VStack(alignment: .leading, spacing: 8) {
                subhead("Analgesic")
                fieldRow("Drug · Dose · Route · Time", value: patient?.paws.pain ?? "—")

                Divider().background(palette.line)
                subhead("Antibiotic")
                fieldRow("Drug · Dose · Route · Time", value: patient?.paws.antibiotics ?? "—")

                Divider().background(palette.line)
                subhead("Other")
                fieldRow("TXA / Calcium / etc.", value: otherMedsSummary)

                Divider().background(palette.line)
                subhead("OTHER · Combat-Pill-Pack · Eye-Shield · Splint · Hypothermia")
                fieldRow("CWMP", value: cwmpLabel)
                fieldRow("Eye-Shield", value: "—")
                fieldRow("Splint", value: patient?.paws.splinting ?? "—")
                fieldRow("Hypothermia-Prevention", value: patient?.march.hypothermiaPrevention ?? "—")
            }
        }
    }

    private var otherMedsSummary: String {
        guard let interventions = patient?.interventions else { return "—" }
        let other = interventions.filter {
            $0.kind == .medication &&
            !($0.description.lowercased().contains("ketamine") ||
              $0.description.lowercased().contains("acetaminophen"))
        }.map { $0.description }
        return other.isEmpty ? "—" : other.joined(separator: ", ")
    }

    private var cwmpLabel: String {
        let pain = patient?.paws.pain?.lowercased() ?? ""
        return pain.contains("combat pill pack") ? "Administered" : "—"
    }

    // MARK: - Section G — Notes

    private var sectionG: some View {
        sectionPanel("G · Notes") {
            VStack(alignment: .leading, spacing: 6) {
                Text(patient?.injuries.joined(separator: " · ") ?? "—")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("(Free-text on physical card. Engine-extracted injuries listed above.)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.fg3)
            }
        }
    }

    // MARK: - Section H — First Responder

    private var sectionH: some View {
        sectionPanel("H · First Responder") {
            VStack(alignment: .leading, spacing: 6) {
                fieldRow("Name", value: state.operatorCallsign)
                fieldRow("Last 4", value: lastFourFromOperatorId)
                fieldRow("Tier", value: state.operatorTier.rawValue)
            }
        }
    }

    private var lastFourFromOperatorId: String {
        // operatorDeviceId looks like "EUD-441-C" — pull a sensible last-4
        // surrogate. Real impl would track responder DoD ID separately.
        let digits = state.operatorDeviceId.filter { $0.isNumber }
        return digits.suffix(4).count == 4 ? String(digits.suffix(4)) : "—"
    }

    // MARK: - Helpers

    private func sectionPanel(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.bg2)

            VStack(alignment: .leading, spacing: 0) {
                content()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
            )
        }
    }

    private func fieldRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(palette.fg2)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(value == "—" ? palette.fg3 : palette.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func subhead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(palette.fg1)
    }
}
