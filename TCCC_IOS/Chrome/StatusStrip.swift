import SwiftUI

struct StatusStrip: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        // Tick the wall-clock once a second so Z/L times stay current.
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            HStack(spacing: 0) {
                recCell(now: context.date)
                divider
                RFGhostBadge(state: state.rfState)
                divider
                casualtyCell
                Spacer(minLength: 0)
                divider
                pageIndicatorCell
                divider
                batteryCell
            }
            .frame(height: Layout.statusStripHeight)
            .padding(.leading, Layout.dynamicIslandClearance)
            .background(palette.bg)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(width: Layout.hairline)
    }

    /// REC cell — recording dot + dual wall-clock (Zulu / Lima).
    /// Per night-pass A1: military medics work both Zulu (UTC, used in
    /// 9-line MEDEVAC + ZMIST timestamps) and Lima (local, used for
    /// situational awareness). Both visible avoids the Z-vs-L confusion
    /// that's a known incident vector in joint-ops documentation.
    private func recCell(now: Date) -> some View {
        HStack(spacing: 6) {
            RecDot()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Self.zuluFormatter.string(from: now))Z")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.fg)
                Text("\(Self.lima(for: now))L")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg2)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 96)
    }

    private static let zuluFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static let limaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm"
        // System default time zone (Lima = local).
        return f
    }()

    private static func lima(for date: Date) -> String {
        limaFormatter.string(from: date)
    }

    private var casualtyCell: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.fg2)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.casualtyId)
                    .tccc(.timer)
                    .foregroundStyle(palette.fg)
                Text(elapsedSession)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg3)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 86)
    }

    /// Session-elapsed timer — moved from REC cell to casualty cell as a
    /// sub-line per night-pass A1. Useful for "how long has this casualty
    /// been with me" visibility without crowding the wall-clock.
    private var elapsedSession: String {
        let elapsed = Int(Date().timeIntervalSince(state.sessionStart))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        return String(format: "+%02d:%02d", h, m)
    }

    private var pageIndicatorCell: some View {
        PageIndicator(
            count: AppState.Screen.allCases.count,
            active: state.screen.rawValue
        )
        .padding(.horizontal, 12)
    }

    private var batteryCell: some View {
        HStack(spacing: 6) {
            BatteryIcon(percent: state.batteryPercent)
            Text("\(state.batteryPercent)%")
                .tccc(.timer)
                .foregroundStyle(palette.fg)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 84)
    }
}

private struct RecDot: View {
    @Environment(\.palette) private var palette
    @State private var pulse: Bool = false

    var body: some View {
        Circle()
            .fill(palette.rec)
            .frame(width: 11, height: 11)
            .scaleEffect(pulse ? 0.85 : 1.0)
            .opacity(pulse ? 0.35 : 1.0)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    withAnimation(.easeInOut(duration: 0.6)) {
                        pulse.toggle()
                    }
                }
            }
    }
}

private struct BatteryIcon: View {
    let percent: Int
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(palette.fg2, lineWidth: 1)
                .frame(width: 22, height: 11)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(palette.fg2)
                        .frame(width: 1.5, height: 4)
                        .offset(x: 2)
                }

            RoundedRectangle(cornerRadius: 1)
                .fill(percent < 20 ? palette.crit : palette.fg)
                .frame(width: max(0, CGFloat(percent) / 100.0 * 18), height: 7)
                .padding(.leading, 2)
        }
        .frame(width: 24, height: 11)
    }
}
