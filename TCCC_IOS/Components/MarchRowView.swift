import SwiftUI
import TCCCDomain

struct MarchRowView: View {
    enum Status {
        case crit
        case warn
        case done
        case na
        case open
    }

    let letter: String
    let title: String
    let detail: String
    let status: Status
    let systemImage: String
    let compact: Bool

    @Environment(\.palette) private var palette

    init(
        letter: String,
        title: String,
        detail: String,
        status: Status,
        systemImage: String,
        compact: Bool = false
    ) {
        self.letter = letter
        self.title = title
        self.detail = detail
        self.status = status
        self.systemImage = systemImage
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 3)

            Text(letter)
                .font(.system(size: compact ? 18 : 22, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(statusColor)
                .frame(width: compact ? 26 : 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.fg2)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                }
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.fg)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            statusIcon
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.vertical, compact ? 6 : 10)
        .padding(.trailing, 12)
    }

    private var statusColor: Color {
        switch status {
        case .crit: palette.crit
        case .warn: palette.warn
        case .done: palette.fg1
        case .na:   palette.fg3
        case .open: palette.accent
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .crit: Image(systemName: "exclamationmark.triangle.fill")
        case .warn: Image(systemName: "exclamationmark.circle")
        case .done: Image(systemName: "checkmark.circle.fill")
        case .na:   Text("—")
        case .open: Image(systemName: "circle")
        }
    }
}

extension PhaseStatus {
    fileprivate var marchStatus: MarchRowView.Status {
        switch self {
        case .done:        .done
        case .inProgress:  .open
        case .notAssessed: .open
        }
    }
}

extension MarchRowView {
    /// Build a row directly from a `PatientState` for one MARCH phase.
    /// The "status color" is more clinically nuanced than the PhaseStatus alone:
    /// it considers whether the finding is critical (e.g., circulation findings
    /// with hypotension flip to .crit).
    static func from(patient: PatientState, phase: MarchPhase) -> MarchRowView {
        switch phase {
        case .massive:
            return MarchRowView(
                letter: "M",
                title: "Massive Hemo",
                detail: hemorrhageDetail(patient.march),
                status: hemorrhageStatus(patient.march),
                systemImage: "drop.fill"
            )
        case .airway:
            return MarchRowView(
                letter: "A",
                title: "Airway",
                detail: airwayDetail(patient.march),
                status: airwayStatus(patient.march),
                systemImage: "lungs"
            )
        case .respiration:
            return MarchRowView(
                letter: "R",
                title: "Respirations",
                detail: respirationDetail(patient.march, vitals: patient.vitals),
                status: respirationStatus(patient.march),
                systemImage: "wind"
            )
        case .circulation:
            return MarchRowView(
                letter: "C",
                title: "Circulation",
                detail: circulationDetail(patient.march, vitals: patient.vitals),
                status: circulationStatus(patient.vitals),
                systemImage: "heart.fill"
            )
        case .head:
            return MarchRowView(
                letter: "H",
                title: "Head / Hypothermia",
                detail: headDetail(patient.march, vitals: patient.vitals),
                status: headStatus(patient.march),
                systemImage: "brain.head.profile"
            )
        }
    }

    // MARK: - Detail / status helpers

    private static func hemorrhageDetail(_ m: MARCHState) -> String {
        if let intervention = m.hemorrhageIntervention {
            if let loc = m.hemorrhageLocation { return "\(intervention) · \(loc)" }
            return intervention
        }
        if let loc = m.hemorrhageLocation { return "Bleeding \(loc)" }
        if m.hemorrhageAssessed { return "No major hemorrhage" }
        return "Not assessed"
    }
    private static func hemorrhageStatus(_ m: MARCHState) -> Status {
        if m.hemorrhageIntervention != nil { return .done }
        if m.hemorrhageIdentified { return .crit }
        if m.hemorrhageAssessed { return .done }
        return .open
    }

    private static func airwayDetail(_ m: MARCHState) -> String {
        if let intervention = m.airwayIntervention {
            if let status = m.airwayStatus { return "\(status.capitalized) · \(intervention)" }
            return intervention
        }
        if let status = m.airwayStatus { return status.capitalized }
        return "Not assessed"
    }
    private static func airwayStatus(_ m: MARCHState) -> Status {
        if m.airwayIntervention != nil { return .done }
        if m.airwayStatus != nil { return .done }
        return .open
    }

    private static func respirationDetail(_ m: MARCHState, vitals: Vitals) -> String {
        var parts: [String] = []
        if let rr = vitals.rr { parts.append("\(rr)/min") }
        if let s = m.respirationStatus { parts.append(s) }
        if let s = m.breathSounds { parts.append(s) }
        if let i = m.respirationIntervention { parts.append(i) }
        return parts.isEmpty ? "Not assessed" : parts.joined(separator: " · ")
    }
    private static func respirationStatus(_ m: MARCHState) -> Status {
        if m.respirationIntervention != nil { return .done }
        let s = (m.respirationStatus ?? "").lowercased()
        if s.contains("labored") || s.contains("absent") { return .warn }
        if m.respirationStatus != nil || m.breathSounds != nil { return .done }
        return .open
    }

    private static func circulationDetail(_ m: MARCHState, vitals: Vitals) -> String {
        var parts: [String] = []
        if let bp = vitals.bp {
            let suffix = bp.palpated ? " P" : ""
            parts.append("\(bp.systolic)/\(bp.diastolic)\(suffix)")
        }
        if let hr = vitals.hr { parts.append("HR \(hr)") }
        if let s = m.pulseStatus { parts.append(s) }
        if let s = m.skinSigns { parts.append(s) }
        if let i = m.circulationIntervention { parts.append(i) }
        return parts.isEmpty ? "Not assessed" : parts.joined(separator: " · ")
    }
    private static func circulationStatus(_ vitals: Vitals) -> Status {
        if let bp = vitals.bp, bp.systolic < 90 { return .crit }
        if let hr = vitals.hr, hr > 130 { return .crit }
        if vitals.bp != nil || vitals.hr != nil { return .done }
        return .open
    }

    private static func headDetail(_ m: MARCHState, vitals: Vitals) -> String {
        var parts: [String] = []
        if let g = vitals.gcs { parts.append("GCS \(g)") }
        if let c = m.consciousness { parts.append(c) }
        if let p = m.pupilResponse { parts.append("Pupils: \(p)") }
        if let h = m.hypothermiaPrevention { parts.append(h) }
        return parts.isEmpty ? "Not assessed" : parts.joined(separator: " · ")
    }
    private static func headStatus(_ m: MARCHState) -> Status {
        if m.consciousness != nil || m.pupilResponse != nil { return .done }
        if m.hypothermiaPrevention != nil { return .open }
        return .open
    }
}
