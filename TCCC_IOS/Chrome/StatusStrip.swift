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
                divider
                locationSourceCell
                Spacer(minLength: 0)
                divider
                pageIndicatorCell
                divider
                memoryCell
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
            RecDot(isActive: state.isRecording)
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

    /// Location readout — the actual GPS grid + accuracy, always visible.
    /// The 9-line LINE 1 is the loudest data we send to the inbound bird, so
    /// the operator can read their position (full-precision MGRS) and its
    /// quality from any screen. When there is no usable fix the cell shows
    /// the capture state (NO FIX / ACQUIRING… / DENIED / RESTRICTED).
    private var locationSourceCell: some View {
        let status = state.locationStatus
        let grid = state.locationGrid
        let color = locationColor(status)
        return HStack(spacing: 6) {
            Image(systemName: locationIcon(status))
                .font(.system(size: 11))
                .foregroundStyle(color)
            if let grid {
                VStack(alignment: .leading, spacing: 0) {
                    Text(grid)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(color)
                    Text(locationDetail(status))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.fg3)
                }
            } else {
                Text(locationDetail(status))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 78, alignment: .leading)
    }

    private func locationColor(_ status: AppState.LocationCaptureStatus) -> Color {
        switch status {
        case .fix:        palette.accent
        case .degraded:   palette.warn
        case .requesting: palette.fg2
        case .noFix, .denied, .restricted, .mgrsUnavailable: palette.crit
        }
    }

    private func locationIcon(_ status: AppState.LocationCaptureStatus) -> String {
        switch status {
        case .fix:        "location.fill"
        case .degraded:   "location.fill"
        case .requesting: "location.circle"
        case .noFix, .denied, .restricted, .mgrsUnavailable: "location.slash"
        }
    }

    private func locationDetail(_ status: AppState.LocationCaptureStatus) -> String {
        switch status {
        case .noFix:                  return "NO FIX"
        case .requesting:             return "ACQUIRING…"
        case .fix(let acc):           return "GPS\(accuracySuffix(acc))"
        case .degraded(let acc):      return "DEGRADED\(accuracySuffix(acc))"
        case .denied:                 return "DENIED"
        case .restricted:             return "RESTRICTED"
        case .mgrsUnavailable:        return "NO GRID"
        }
    }

    private func accuracySuffix(_ meters: Double?) -> String {
        guard let m = meters, m >= 0 else { return "" }
        return " ±\(Int(m.rounded()))m"
    }

    private var pageIndicatorCell: some View {
        PageIndicator(
            count: AppState.Screen.allCases.count,
            active: state.screen.rawValue
        )
        .padding(.horizontal, 12)
    }

    /// Memory-headroom chip per night-pass A3. Shows bytes available
    /// before iOS would jetsam-kill the foreground app. Color shifts
    /// from fg2 (plenty) to warn (~500 MB) to crit (~200 MB) so a
    /// medic notices when the on-device LLMs / ASR are pushing the
    /// budget.
    /// Memory-headroom chip. Reads `MemoryStat.availableBytes()` on
    /// each TimelineView tick (the same 1Hz cadence as the dual
    /// clock).
    private var memoryCell: some View {
        let label = MemoryStat.chipLabel()
        let pressure = MemoryStat.pressure()
        let color: Color
        switch pressure {
        case .crit:    color = palette.crit
        case .warn:    color = palette.warn
        case .normal:  color = palette.fg2
        case .unknown: color = palette.fg3
        }
        return HStack(spacing: 6) {
            Image(systemName: "memorychip")
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 70)
    }

    private var batteryCell: some View {
        let percent = state.batteryPercent
        let charging = state.batteryIsCharging
        return HStack(spacing: 6) {
            BatteryIcon(percent: percent, charging: charging)
            Text(percent >= 0 ? "\(percent)%" : "—")
                .tccc(.timer)
                .foregroundStyle(palette.fg)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 84)
    }
}

private struct RecDot: View {
    let isActive: Bool
    @Environment(\.palette) private var palette
    @State private var pulse: Bool = false

    var body: some View {
        Circle()
            .fill(isActive ? palette.rec : palette.fg3)
            .frame(width: 11, height: 11)
            .scaleEffect(isActive && pulse ? 0.85 : 1.0)
            .opacity(isActive ? (pulse ? 0.35 : 1.0) : 0.5)
            .task(id: isActive) {
                guard isActive else { return }
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
    var charging: Bool = false
    @Environment(\.palette) private var palette

    var body: some View {
        // Unknown (simulator / monitoring off) → render an empty cell.
        let clamped = max(0, min(100, percent))
        let fillColor: Color = charging ? palette.accent
            : (percent >= 0 && percent < 20 ? palette.crit : palette.fg)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .stroke(palette.fg2, lineWidth: 1)
                .frame(width: 22, height: 11)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(palette.fg2)
                        .frame(width: 1.5, height: 4)
                        .offset(x: 2)
                }

            if percent >= 0 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(fillColor)
                    .frame(width: max(0, CGFloat(clamped) / 100.0 * 18), height: 7)
                    .padding(.leading, 2)
            }

            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(palette.bg)
                    .frame(width: 22, alignment: .center)
            }
        }
        .frame(width: 24, height: 11)
    }
}
