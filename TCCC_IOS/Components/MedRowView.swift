import SwiftUI
import TCCCDomain

struct MedRowView: View {
    let intervention: Intervention
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timestampShort)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg2)
                .frame(width: 52, alignment: .leading)

            Image(systemName: kindIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
                Text(intervention.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.fg)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
    }

    private var timestampShort: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: intervention.timestamp)
    }

    private var kindLabel: String {
        switch intervention.kind {
        case .tourniquet:           "TQ"
        case .pressureDressing,
             .dressing:             "DRESSING"
        case .chestSeal:            "CHEST SEAL"
        case .needleDecompression:  "NDC"
        case .ivAccess:             "IV"
        case .ioAccess:             "IO"
        case .medication:           "MED"
        case .antibiotic:           "ABX"
        case .painManagement:       "PAIN"
        case .woundCare:            "WOUND"
        case .npa:                  "NPA"
        case .surgicalAirway:       "SURG AW"
        case .splint:               "SPLINT"
        case .hypothermiaPrevention: "HYPO"
        case .other:                "INT"
        }
    }

    private var kindIcon: String {
        switch intervention.kind {
        case .medication, .painManagement, .antibiotic, .tourniquet: "syringe"
        case .ivAccess, .ioAccess:     "drop.fill"
        case .chestSeal, .needleDecompression: "lungs"
        case .npa, .surgicalAirway:    "wind"
        case .splint:                  "ruler"
        case .pressureDressing, .dressing, .woundCare, .other: "bandage"
        case .hypothermiaPrevention:   "thermometer.snowflake"
        }
    }
}
