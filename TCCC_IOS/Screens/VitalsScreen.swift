import SwiftUI
import TCCCDomain

/// Screen 02 — Vitals.
///
/// 2-column grid `1.3fr / 1fr`, 8pt gap, 8pt outer padding (per design §5.2).
///
/// Left column (vertical stack):
///   - 3-col BigVital strip (HR / BP / SpO₂)
///   - ECG · LEAD II panel (synthetic PQRST canvas, flexes to fill)
///   - 4-col SmallVital strip (RESP / GCS / TEMP / CAP RE)
///
/// Right column:
///   - TREND · LAST 15 MIN panel (Canvas trend chart, 3 series)
///   - INTERVENTIONS panel (filtered to non-medication kinds)
struct VitalsScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    private var patient: PatientState? { state.primaryPatient }

    private var interventionsToShow: [Intervention] {
        guard let patient else { return [] }
        return patient.interventions
            .filter { InterventionRow.nonMedicationKinds.contains($0.kind) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .vitals,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: "LAST UPDATE",
                trailingKickerValue: lastUpdateLabel
            )

            GeometryReader { geo in
                let totalGap = Layout.gridGap
                let usable = geo.size.width - totalGap
                // 1.10 / 1.00 split — set via layout playground.
                let wL = usable * (1.10 / 2.10)
                let wR = usable - wL
                HStack(alignment: .top, spacing: totalGap) {
                    leftColumn
                        .frame(width: wL, height: geo.size.height)
                    rightColumn
                        .frame(width: wR, height: geo.size.height)
                }
            }
            .padding(Layout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterHints(
                leadingLabel: "CAPTURE",
                trailingLabel: "TCCC CARD",
                onSettings: { state.settingsOpen = true },
                onQuickActions: { state.quickActionsOpen = true }
            )
        }
        .background(palette.bg)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: Layout.gridGap) {
            bigVitalStrip
            ecgPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            smallVitalStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bigVitalStrip: some View {
        // 3-col grid 1.00 / 1.50 / 1.00 — set via layout playground.
        // BP is 1.5x wider than HR/SpO₂ to fit "80/40 mmHg · PAL" without
        // forcing minimumScaleFactor on the value font.
        GeometryReader { geo in
            let gaps = Layout.gridGap * 2
            let usable = geo.size.width - gaps
            let wHR = usable * (1.0 / 3.5)
            let wBP = usable * (1.5 / 3.5)
            let wSP = usable - wHR - wBP
            HStack(spacing: Layout.gridGap) {
                hrCard.frame(width: wHR, height: geo.size.height)
                bpCard.frame(width: wBP, height: geo.size.height)
                spo2Card.frame(width: wSP, height: geo.size.height)
            }
        }
        .frame(height: 137)
    }

    private var hrCard: some View {
        let hr = patient?.vitals.hr
        let value = hr.map { "\($0)" } ?? "—"
        let status: BigVital.Status = hrStatus(hr)
        let sub: String = hrSubline(hr)
        return BigVital(
            label: "Heart Rate",
            value: value,
            unit: "BPM",
            sub: sub,
            status: status,
            icon: "heart.fill"
        )
    }

    private var bpCard: some View {
        let bp = patient?.vitals.bp
        let value: String = bp.map {
            $0.palpated ? "\($0.systolic)/P" : "\($0.systolic)/\($0.diastolic)"
        } ?? "—"
        let unit: String = (bp?.palpated == true) ? "mmHg · PAL" : "mmHg"
        let status: BigVital.Status = bpStatus(bp?.systolic)
        let sub: String = bpSubline(bp?.systolic)
        return BigVital(
            label: "Blood Pressure",
            value: value,
            unit: unit,
            sub: sub,
            status: status,
            icon: "waveform.path.ecg"
        )
    }

    private var spo2Card: some View {
        let spo2 = patient?.vitals.spo2
        let value = spo2.map { "\($0)" } ?? "—"
        let status: BigVital.Status = spo2Status(spo2)
        let sub: String = spo2Subline(spo2)
        return BigVital(
            label: "SpO₂",
            value: value,
            unit: "%",
            sub: sub,
            status: status,
            icon: "lungs.fill"
        )
    }

    private var ecgPanel: some View {
        Panel("ECG · Lead II", titleIcon: "heart.fill", action: "SIM", padded: true) {
            ECGWave()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 90)
        }
    }

    private var smallVitalStrip: some View {
        HStack(spacing: Layout.gridGap) {
            respCard
                .frame(maxWidth: .infinity)
            gcsCard
                .frame(maxWidth: .infinity)
            tempCard
                .frame(maxWidth: .infinity)
            capRefillCard
                .frame(maxWidth: .infinity)
        }
    }

    private var respCard: some View {
        let rr = patient?.vitals.rr
        return SmallVital(
            label: "Resp",
            value: rr.map { "\($0)" } ?? "—",
            unit: "/min",
            isWarn: respIsWarn(rr),
            icon: "wind"
        )
    }

    private var gcsCard: some View {
        let gcs = patient?.vitals.gcs
        let unit: String = gcs.map { gcsBreakdownLabel($0) } ?? "E? V? M?"
        return SmallVital(
            label: "GCS",
            value: gcs.map { "\($0)" } ?? "—",
            unit: unit,
            isWarn: gcsIsWarn(gcs),
            icon: "brain.head.profile"
        )
    }

    private var tempCard: some View {
        let t = patient?.vitals.temperatureCelsius
        let value: String = t.map { String(format: "%.1f", $0) } ?? "—"
        return SmallVital(
            label: "Temp",
            value: value,
            unit: "°C",
            isWarn: tempIsWarn(t),
            icon: "thermometer.medium"
        )
    }

    private var capRefillCard: some View {
        let cap = patient?.vitals.capillaryRefillSeconds
        let value: String = cap.map { String(format: "%.1f", $0) } ?? "—"
        return SmallVital(
            label: "Cap Re",
            value: value,
            unit: "sec",
            isWarn: capIsWarn(cap),
            icon: "timer"
        )
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(spacing: Layout.gridGap) {
            trendPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            interventionsPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trendPanel: some View {
        Panel(
            "Trend · Last 15 Min",
            titleIcon: "chart.xyaxis.line",
            action: "HR · BP · SpO₂",
            padded: true
        ) {
            TrendChart(history: state.vitalsHistory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 120)
        }
    }

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
            Text("TQ · dressings · CS · NDC · IV / IO · NPA · splint")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
    }

    // MARK: - Status helpers

    private func hrStatus(_ hr: Int?) -> BigVital.Status {
        guard let hr else { return .normal }
        if hr > 130 || hr < 50 { return .crit }
        if hr > 110 || hr < 60 { return .warn }
        return .normal
    }

    private func hrSubline(_ hr: Int?) -> String {
        guard let hr else { return "Awaiting reading" }
        if hr > 130 { return "↑ Tachycardia" }
        if hr > 110 { return "Mild tachycardia" }
        if hr < 50  { return "↓ Bradycardia" }
        if hr < 60  { return "Mild bradycardia" }
        return "Sinus"
    }

    private func bpStatus(_ systolic: Int?) -> BigVital.Status {
        guard let s = systolic else { return .normal }
        if s < 90 || s > 180 { return .crit }
        if s < 100 || s > 160 { return .warn }
        return .normal
    }

    private func bpSubline(_ systolic: Int?) -> String {
        guard let s = systolic else { return "Awaiting reading" }
        if s < 90  { return "↓ Hypotension" }
        if s < 100 { return "Borderline low" }
        if s > 180 { return "↑ Hypertension" }
        if s > 160 { return "Elevated" }
        return "Within range"
    }

    private func spo2Status(_ spo2: Int?) -> BigVital.Status {
        guard let s = spo2 else { return .normal }
        if s < 90 { return .crit }
        if s < 95 { return .warn }
        return .normal
    }

    private func spo2Subline(_ spo2: Int?) -> String {
        guard let s = spo2 else { return "Awaiting reading" }
        if s < 90 { return "Hypoxic — supplement O₂" }
        if s < 95 { return "Room air" }
        return "Adequate"
    }

    private func respIsWarn(_ rr: Int?) -> Bool {
        guard let rr else { return false }
        return rr > 24 || rr < 10
    }

    private func gcsIsWarn(_ gcs: Int?) -> Bool {
        guard let gcs else { return false }
        return gcs < 14
    }

    /// We only ever store a total GCS in `Vitals` — the breakdown line is a
    /// best-effort from the total: GCS 15 → "E4 V5 M6"; otherwise we display
    /// a generic badge that signals "see card for breakdown".
    private func gcsBreakdownLabel(_ total: Int) -> String {
        switch total {
        case 15: "E4 V5 M6"
        case 14: "E3 V5 M6"
        case 13: "E3 V4 M6"
        case 12: "E3 V4 M5"
        default: "/ 15"
        }
    }

    private func tempIsWarn(_ t: Double?) -> Bool {
        guard let t else { return false }
        return t < 36.0 || t > 38.0
    }

    private func capIsWarn(_ cap: Double?) -> Bool {
        guard let cap else { return false }
        return cap > 2.5
    }

    // MARK: - Header status

    private var lastUpdateLabel: String {
        guard let last = state.vitalsHistory.samples.last else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: last.timestamp)
    }
}
