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
    var action: (() -> Void)? = nil

    @Environment(\.palette) private var palette

    var body: some View {
        if let action, isReady {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isReady ? palette.fg : palette.fg2)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        Text(isReady ? "✓ READY" : "PEND")
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(isReady ? palette.ok : palette.fg2)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .overlay(
                Rectangle()
                    .strokeBorder(isReady ? palette.ok : palette.fg3, lineWidth: Layout.hairline)
            )
    }
}
