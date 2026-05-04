import SwiftUI

/// Compact export-status card for Screen 05 (Handoff), Column 3.
///
/// Layout per design brief §5.5:
///   1px border · 8×10 padding · `palette.bg` background.
///   icon (14pt) + label + sub line (11pt mono `palette.fg2`)
///   + status pill ("✓ READY" `palette.ok` or "PENDING" `palette.fg2`).
struct ExportCard: View {
    let icon: String
    let title: String       // "DD-1380 PDF"
    let detail: String      // "48 KB" or "Pending PDFKit"
    let isReady: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isReady ? palette.fg : palette.fg2)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg2)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            statusPill
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(palette.bg)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    private var statusPill: some View {
        Text(isReady ? "✓ READY" : "PENDING")
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(isReady ? palette.ok : palette.fg2)
            .textCase(.uppercase)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .overlay(
                Rectangle()
                    .strokeBorder(isReady ? palette.ok : palette.fg3, lineWidth: Layout.hairline)
            )
    }
}
