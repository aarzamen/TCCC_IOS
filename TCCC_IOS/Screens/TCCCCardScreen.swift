import SwiftUI
import TCCCDomain

struct TCCCCardScreen: View {
    let state: AppState
    @Environment(\.palette) private var palette

    @State private var showBackOfCard: Bool = false

    private var patient: PatientState? { state.primaryPatient }

    private var medRows: [Intervention] {
        guard let patient else { return [] }
        return patient.interventions.filter { $0.kind == .medication }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                screen: .tcccCard,
                total: AppState.Screen.allCases.count,
                trailingKickerLabel: showBackOfCard ? "VIEW" : "STATUS",
                trailingKickerValue: showBackOfCard ? "BACK · §D-H" : cardStatus
            )

            // Quick toggle between front and back of card.
            HStack(spacing: 8) {
                Button {
                    showBackOfCard = false
                } label: {
                    sideTabLabel("FRONT · §A-C", isActive: !showBackOfCard)
                }
                .buttonStyle(.plain)
                Button {
                    showBackOfCard = true
                } label: {
                    sideTabLabel("BACK · §D-H", isActive: showBackOfCard)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, Layout.outerPadding)
            .padding(.top, 6)

            if showBackOfCard {
                BackOfCardView(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: Layout.gridGap) {
                    casualtyPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    marchPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: Layout.gridGap) {
                        if !state.pendingWarnings.isEmpty {
                            WarningBanner(warnings: state.pendingWarnings)
                        }
                        pawsPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        medsPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(Layout.outerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            FooterHints(
                state: state,
                leadingLabel: "VITALS",
                trailingLabel: "MEDEVAC"
            )
        }
        .background(palette.bg)
    }

    private func sideTabLabel(_ text: String, isActive: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(isActive ? palette.accent : palette.fg2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .overlay(
                Rectangle()
                    .strokeBorder(isActive ? palette.accent : palette.line, lineWidth: Layout.hairline)
            )
    }

    // MARK: - Casualty panel

    private var casualtyPanel: some View {
        Panel(
            "Casualty · \(state.casualtyId)",
            action: casualtyHeaderAction,
            padded: true
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 6
                ) {
                    Field(label: "Name", value: state.casualtyName)
                    Field(label: "Unit", value: state.casualtyUnit)
                    Field(label: "Svc #", value: state.casualtyServiceNumberMasked)
                    Field(label: "Allrg", value: state.casualtyAllergies)
                }

                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)

                BodyMap(patient: patient)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 140, maxHeight: 160)

                bodyMapLegend
            }
        }
    }

    private var casualtyHeaderAction: String {
        guard let patient else { return "—" }
        var parts: [String] = []
        if let moi = patient.mechanismOfInjury { parts.append(moi.uppercased()) }
        if let cls = patient.classification { parts.append(cls.rawValue.uppercased()) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var bodyMapLegend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Circle().fill(palette.crit).frame(width: 6, height: 6)
                Text("Wound").font(.system(size: 9, weight: .semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(palette.fg2)
            }
            HStack(spacing: 4) {
                Rectangle().fill(palette.accent).frame(width: 10, height: 3)
                Text("TQ").font(.system(size: 9, weight: .semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(palette.fg2)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - MARCH panel

    private var marchPanel: some View {
        // 6-row rendering per 2026 sprint Task 2.2: M, A, R, C, H-Hypo, H-TBI.
        // The legacy single H row is split into two sub-rows mirroring
        // 2026 §7 (hypothermia) and §8 (TBI).
        let phases: [MarchPhase] = [.massive, .airway, .respiration, .circulation]
        return Panel("M.A.R.C.H.", action: marchAction, padded: false) {
            VStack(spacing: 0) {
                ForEach(phases, id: \.self) { phase in
                    if let patient {
                        MarchRowView.from(patient: patient, phase: phase, compact: true)
                    } else {
                        emptyMarchRow(phase: phase)
                    }
                    Rectangle()
                        .fill(palette.line)
                        .frame(height: Layout.hairline)
                }
                // H-Hypothermia
                if let patient {
                    MarchRowView.hypothermiaRow(patient: patient, compact: true)
                } else {
                    emptyHypothermiaRow
                }
                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)
                // H-TBI
                if let patient {
                    MarchRowView.tbiRow(patient: patient, compact: true)
                } else {
                    emptyTbiRow
                }
            }
        }
    }

    private var emptyHypothermiaRow: some View {
        MarchRowView(
            letter: "H",
            title: "Hypothermia",
            detail: "Not assessed",
            status: .open,
            systemImage: "thermometer.snowflake",
            compact: true
        )
    }

    private var emptyTbiRow: some View {
        MarchRowView(
            letter: "H",
            title: "TBI",
            detail: "Not assessed",
            status: .open,
            systemImage: "brain.head.profile",
            compact: true
        )
    }

    private var marchAction: String {
        if patient == nil { return "—" }
        return "ASSESSMENT"
    }

    private func emptyMarchRow(phase: MarchPhase) -> some View {
        MarchRowView(
            letter: phaseLetter(phase),
            title: phaseTitle(phase),
            detail: "Not assessed",
            status: .open,
            systemImage: phaseIcon(phase)
        )
    }

    private func phaseLetter(_ phase: MarchPhase) -> String {
        switch phase {
        case .massive: "M"
        case .airway: "A"
        case .respiration: "R"
        case .circulation: "C"
        case .head: "H"
        }
    }

    private func phaseTitle(_ phase: MarchPhase) -> String {
        switch phase {
        case .massive: "Massive Hemo"
        case .airway: "Airway"
        case .respiration: "Respirations"
        case .circulation: "Circulation"
        case .head: "Head / Hypothermia"
        }
    }

    private func phaseIcon(_ phase: MarchPhase) -> String {
        switch phase {
        case .massive: "drop.fill"
        case .airway: "lungs"
        case .respiration: "wind"
        case .circulation: "heart.fill"
        case .head: "brain.head.profile"
        }
    }

    // MARK: - PAWS panel

    private var pawsPanel: some View {
        Panel("P.A.W.S.", padded: false) {
            VStack(spacing: 0) {
                let rows: [PAWSRowView] = patient.map {
                    PAWSRowView.rows(for: $0.paws, march: $0.march)
                } ?? defaultPAWSRows()
                ForEach(0..<rows.count, id: \.self) { idx in
                    rows[idx]
                    if idx < rows.count - 1 {
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: Layout.hairline)
                    }
                }
            }
        }
    }

    private func defaultPAWSRows() -> [PAWSRowView] {
        // No patient → MARCH not assessed → PAWS dormant.
        PAWSRowView.rows(for: PAWSAssessment(), march: MARCHState())
    }

    // MARK: - Meds panel

    private var medsPanel: some View {
        Panel("Meds Log", titleIcon: "syringe", action: medsAction, padded: false) {
            if medRows.isEmpty {
                emptyMedsHint
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(medRows) { med in
                            MedRowView(intervention: med)
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: Layout.hairline)
                        }
                    }
                }
            }
        }
    }

    private var medsAction: String {
        medRows.isEmpty ? "0" : "\(medRows.count) LOGGED"
    }

    private var emptyMedsHint: some View {
        VStack(spacing: 6) {
            Text("No medications logged")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            Text("Tap MED GIVEN on Live Capture to log")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
    }

    // MARK: - Helpers

    private var cardStatus: String {
        if patient == nil { return "EMPTY" }
        return "DRAFT"
    }
}

