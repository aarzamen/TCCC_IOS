import SwiftUI

/// Export availability is separate from clinical completeness or review.
struct ExportCard: View {
    let icon: String
    let title: String       // "DD-1380 PDF"
    let detail: String      // "48 KB" or "Pending PDFKit"
    let isReady: Bool
    var actionLabel: String = "Share"
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.fg)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.fg2)
                .fixedSize(horizontal: false, vertical: true)
            if isReady, action != nil {
                Label(actionLabel, systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: Layout.minHitTarget, alignment: .leading)
        .background(palette.bg)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

}
