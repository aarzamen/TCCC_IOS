import SwiftUI

/// Large vitals card used in Screen 02 (Vitals) — primary trio: HR, BP, SpO₂.
///
/// Spec (design brief §5.2):
/// - 1px line border, 2pt top stripe in status color
/// - bg-1, padding 10×14×12
/// - 52pt mono 700 value with -0.03em letter-spacing (use `.tracking(-1.5)`)
/// - 11pt unit to right of value, 12pt sub in fg-2
/// - Header status pip ("● CRIT" / "● WARN") matches `status`
struct BigVital: View {
    enum Status {
        case normal
        case warn
        case crit
    }

    let label: String
    let value: String
    let unit: String
    let sub: String
    let status: Status
    let icon: String

    @Environment(\.palette) private var palette

    init(
        label: String,
        value: String,
        unit: String,
        sub: String,
        status: Status,
        icon: String
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.sub = sub
        self.status = status
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 2pt top stripe in status color
            Rectangle()
                .fill(stripeColor)
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 6) {
                header
                valueRow
                subline
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.fg2)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)

            Spacer(minLength: 0)

            statusPip
        }
    }

    @ViewBuilder
    private var statusPip: some View {
        switch status {
        case .crit:
            HStack(spacing: 4) {
                Circle()
                    .fill(palette.crit)
                    .frame(width: 6, height: 6)
                Text("CRIT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.crit)
            }
        case .warn:
            HStack(spacing: 4) {
                Circle()
                    .fill(palette.warn)
                    .frame(width: 6, height: 6)
                Text("WARN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.warn)
            }
        case .normal:
            EmptyView()
        }
    }

    // MARK: - Value + unit

    private var valueRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(value)
                .tccc(.bigVital)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(unit)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
                .lineLimit(1)
        }
    }

    private var subline: some View {
        Text(sub)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.fg2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: - Colors

    private var valueColor: Color {
        switch status {
        case .crit:   palette.crit
        case .warn:   palette.warn
        case .normal: palette.fg
        }
    }

    private var stripeColor: Color {
        switch status {
        case .crit:   palette.crit
        case .warn:   palette.warn
        case .normal: palette.lineStrong
        }
    }
}
