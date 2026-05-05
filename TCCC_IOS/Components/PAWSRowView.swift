import SwiftUI
import TCCCDomain

struct PAWSRowView: View {
    let letter: String
    let title: String
    let detail: String
    let isOpen: Bool
    let systemImage: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(isOpen ? palette.accent : palette.fg1)
                .frame(width: 3)

            Text(letter)
                .font(.system(size: 18, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(isOpen ? palette.accent : palette.fg1)
                .frame(width: 26)

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
        }
        .padding(.vertical, 6)
        .padding(.trailing, 12)
    }
}

extension PAWSRowView {
    /// Build the four PAWS rows. PAWS is **gated on MARCH assessment** per
    /// 2026-sprint Task 2.1: until every MARCH phase has at least an
    /// in-progress assessment, all PAWS rows render with placeholder "—"
    /// detail and `isOpen = true`. This prevents the "Antibiotics Pending"
    /// hint from appearing before MARCH has been worked through.
    static func rows(
        for paws: PAWSAssessment,
        march: MARCHState
    ) -> [PAWSRowView] {
        let dormant = !march.allPhasesAssessed
        return [
            PAWSRowView(
                letter: "P",
                title: "Pain",
                detail: dormant ? "—" : (paws.pain ?? "—"),
                isOpen: dormant || paws.pain == nil,
                systemImage: "syringe"
            ),
            PAWSRowView(
                letter: "A",
                title: "Antibiotics",
                detail: dormant ? "—" : (paws.antibiotics ?? "Pending"),
                isOpen: dormant || paws.antibiotics == nil,
                systemImage: "pills.fill"
            ),
            PAWSRowView(
                letter: "W",
                title: "Wounds",
                detail: dormant ? "—" : (paws.wounds ?? "—"),
                isOpen: dormant || paws.wounds == nil,
                systemImage: "bandage"
            ),
            PAWSRowView(
                letter: "S",
                title: "Splinting",
                detail: dormant ? "—" : (paws.splinting ?? "N/A"),
                isOpen: dormant || paws.splinting == nil,
                systemImage: "ruler"
            ),
        ]
    }
}
