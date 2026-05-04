import SwiftUI
import TCCCDomain

/// Single intervention row used in the Screen 02 INTERVENTIONS panel.
///
/// 4-column grid: 54pt timestamp / 18pt icon / 60pt kind label / 1fr description.
/// 1px bottom hairline drawn by the parent stack. Hot rows tint with `palette.bg2`
/// and accent the icon + kind label.
///
/// Kind labels mirror `MedRowView.swift` but trimmed to non-medication kinds:
/// TQ / DRESSING / CS / NDC / IV / IO / NPA / SPLINT.
struct InterventionRow: View {
    let intervention: Intervention
    let isHot: Bool

    @Environment(\.palette) private var palette

    init(intervention: Intervention, isHot: Bool = false) {
        self.intervention = intervention
        self.isHot = isHot
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timestampShort)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg2)
                .frame(width: 54, alignment: .leading)

            Image(systemName: kindIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHot ? palette.accent : palette.fg2)
                .frame(width: 18, alignment: .leading)
                .padding(.top, 1)

            Text(kindLabel)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(isHot ? palette.accent : palette.fg2)
                .textCase(.uppercase)
                .frame(width: 60, alignment: .leading)
                .padding(.top, 2)

            Text(intervention.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.fg)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHot ? palette.bg2 : Color.clear)
    }

    private var timestampShort: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: intervention.timestamp)
    }

    private var kindLabel: String {
        switch intervention.kind {
        case .tourniquet:                       "TQ"
        case .pressureDressing, .dressing:      "DRESSING"
        case .chestSeal:                        "CS"
        case .needleDecompression:              "NDC"
        case .ivAccess:                         "IV"
        case .ioAccess:                         "IO"
        case .npa:                              "NPA"
        case .surgicalAirway:                   "SURG AW"
        case .splint:                           "SPLINT"
        case .woundCare:                        "WOUND"
        case .hypothermiaPrevention:            "HYPO"
        // Medication-class kinds shouldn't reach this row in normal flow,
        // but keep mapping defined so the UI never crashes if filtering
        // is loosened later.
        case .medication, .painManagement, .antibiotic: "MED"
        case .other:                            "INT"
        }
    }

    private var kindIcon: String {
        switch intervention.kind {
        case .tourniquet:                       "bandage.fill"
        case .pressureDressing, .dressing:      "bandage"
        case .chestSeal:                        "shield.lefthalf.filled"
        case .needleDecompression:              "lungs"
        case .ivAccess, .ioAccess:              "drop.fill"
        case .npa, .surgicalAirway:             "wind"
        case .splint:                           "ruler"
        case .woundCare:                        "bandage"
        case .hypothermiaPrevention:            "thermometer.snowflake"
        case .medication, .painManagement, .antibiotic: "syringe"
        case .other:                            "cross.case.fill"
        }
    }
}

extension InterventionRow {
    /// Interventions surfaced on Screen 02 — the hands-on equipment work, not
    /// medications (those live on Screen 03 in the Meds Log panel).
    static let nonMedicationKinds: Set<InterventionKind> = [
        .tourniquet,
        .pressureDressing,
        .dressing,
        .chestSeal,
        .needleDecompression,
        .ivAccess,
        .ioAccess,
        .npa,
        .surgicalAirway,
        .splint,
        .woundCare,
        .hypothermiaPrevention,
        .other,
    ]

    /// Hot kinds (palette.bg2 background, accent label/icon) — the
    /// life-threats and immediate sterility risks worth the medic's eye.
    static let hotKinds: Set<InterventionKind> = [
        .tourniquet,
        .chestSeal,
        .needleDecompression,
    ]
}
