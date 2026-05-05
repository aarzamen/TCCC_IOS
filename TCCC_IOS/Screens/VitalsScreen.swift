import SwiftUI
import TCCCDomain

/// Screen 02 — Vital Signs Log (DD 1380 Section C grid).
///
/// Layout per the 2026 sprint Phase 4 reframe:
///   - 4 timestamped columns × 7 rows
///   - Rows: Time, Pulse (Rate & Loc), Blood Pressure, Respiratory Rate,
///     Pulse Ox % O2 Sat, AVPU, Pain Scale (0-10)
///   - Empty columns render placeholder dashes
///
/// Reference: reference/rubric/extracted/dd1380_field_inventory.json fields
/// with section_identifier "C".
///
/// **Editing is read-only for now.** Future work: tap-to-edit cells plus a
/// "Add Reading" affordance to capture a new timestamped column. The
/// engine's auto-snapshot covers the read-path until then.
struct VitalsScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    private var patient: PatientState? { state.primaryPatient }

    private var interventionsToShow: [Intervention] {
        guard let patient else { return [] }
        return patient.interventions
            .filter { InterventionRow.nonMedicationKinds.contains($0.kind) }
    }

    /// Always exactly 4 column slots — pads with nil for missing readings.
    private var fourColumns: [AppState.SectionCReading?] {
        var cols: [AppState.SectionCReading?] = state.vitalsLog.map { $0 }
        while cols.count < 4 { cols.append(nil) }
        return cols
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .vitals,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "READINGS",
                trailingKickerValue: "\(state.vitalsLog.count) / 4"
            )

            HStack(alignment: .top, spacing: Layout.gridGap) {
                sectionCPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                interventionsPanel
                    .frame(width: 240, alignment: .top)
                    .frame(maxHeight: .infinity)
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(
                state: state,
                leadingLabel: "CAPTURE",
                trailingLabel: "TCCC CARD"
            )
        }
        .background(palette.bg)
    }

    // MARK: - DD 1380 §C grid

    private var sectionCPanel: some View {
        Panel(
            "DD 1380 · Section C",
            titleIcon: "tablecells",
            action: gridAction,
            padded: false
        ) {
            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    rowDivider
                    cRow(label: "Time",       values: fourColumns.map { columnTimeString($0) })
                    rowDivider
                    cRow(label: "Pulse",      values: fourColumns.map { pulseValue($0) })
                    rowDivider
                    cRow(label: "Blood Pressure", values: fourColumns.map { bpValue($0) })
                    rowDivider
                    cRow(label: "Respiratory Rate", values: fourColumns.map { rrValue($0) })
                    rowDivider
                    cRow(label: "SpO₂ %",     values: fourColumns.map { spo2Value($0) })
                    rowDivider
                    cRow(label: "AVPU",       values: fourColumns.map { avpuValue($0) })
                    rowDivider
                    cRow(label: "Pain (0-10)", values: fourColumns.map { _ in "—" })
                }
            }
        }
    }

    private var gridAction: String {
        state.vitalsLog.isEmpty ? "AWAITING DATA" : "READ-ONLY · DRAFT"
    }

    // MARK: - Grid header

    private var headerRow: some View {
        HStack(spacing: 0) {
            cellLabel("ROW", isHeader: true)
                .frame(width: rowLabelWidth, alignment: .leading)
            ForEach(0..<4, id: \.self) { idx in
                colDivider
                cellLabel("COL \(idx + 1)", isHeader: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.bg2)
    }

    private func cRow(label: String, values: [String]) -> some View {
        HStack(spacing: 0) {
            cellLabel(label.uppercased(), isHeader: false)
                .frame(width: rowLabelWidth, alignment: .leading)
            ForEach(0..<min(values.count, 4), id: \.self) { idx in
                colDivider
                Text(values[idx])
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(values[idx] == "—" ? palette.fg3 : palette.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func cellLabel(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(.system(size: isHeader ? 9 : 10, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(isHeader ? palette.fg2 : palette.fg1)
            .textCase(.uppercase)
    }

    private var colDivider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(width: Layout.hairline)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 6)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(height: Layout.hairline)
    }

    private let rowLabelWidth: CGFloat = 110

    // MARK: - Row formatting

    private func columnTimeString(_ r: AppState.SectionCReading?) -> String {
        guard let r else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: r.timestamp)
    }

    private func pulseValue(_ r: AppState.SectionCReading?) -> String {
        guard let r, let hr = r.vitals.hr else { return "—" }
        return "\(hr) bpm"
    }

    private func bpValue(_ r: AppState.SectionCReading?) -> String {
        guard let r, let bp = r.vitals.bp else { return "—" }
        let suffix = bp.palpated ? " P" : ""
        return "\(bp.systolic)/\(bp.diastolic)\(suffix)"
    }

    private func rrValue(_ r: AppState.SectionCReading?) -> String {
        guard let r, let rr = r.vitals.rr else { return "—" }
        return "\(rr)"
    }

    private func spo2Value(_ r: AppState.SectionCReading?) -> String {
        guard let r, let spo2 = r.vitals.spo2 else { return "—" }
        return "\(spo2)%"
    }

    private func avpuValue(_ r: AppState.SectionCReading?) -> String {
        guard let r, let avpu = r.avpu else { return "—" }
        // DD 1380 allowed values are A/V/P/U single letters.
        let letter: String
        switch avpu.lowercased() {
        case "alert":         letter = "A"
        case "voice":         letter = "V"
        case "pain":          letter = "P"
        case "unresponsive":  letter = "U"
        default:              letter = avpu.prefix(1).uppercased()
        }
        return letter
    }

    // MARK: - Interventions panel (preserved from Phase 1)

    private var interventionsPanel: some View {
        Panel(
            "Interventions",
            titleIcon: "cross.case.fill",
            action: interventionsAction,
            padded: false
        ) {
            if interventionsToShow.isEmpty {
                emptyInterventionsHint
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(interventionsToShow) { intervention in
                            InterventionRow(
                                intervention: intervention,
                                isHot: InterventionRow.hotKinds.contains(intervention.kind)
                            )
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: Layout.hairline)
                        }
                    }
                }
            }
        }
    }

    private var interventionsAction: String {
        let n = interventionsToShow.count
        return n == 0 ? "0 LOGGED" : "\(n) LOGGED"
    }

    private var emptyInterventionsHint: some View {
        VStack(spacing: 6) {
            Text("No interventions logged")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            Text("TQ · dressings · CS · NDC · IV / IO · NPA")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
    }
}
