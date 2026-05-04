import SwiftUI

struct StatusStrip: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            recCell
            divider
            RFGhostBadge(state: state.rfState)
            divider
            casualtyCell
            divider
            gpsCell
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

    private var divider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(width: Layout.hairline)
    }

    private var recCell: some View {
        HStack(spacing: 6) {
            RecDot()
            Text(elapsedTimer)
                .tccc(.timer)
                .foregroundStyle(palette.fg)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 96)
    }

    private var elapsedTimer: String {
        let elapsed = Int(Date().timeIntervalSince(state.sessionStart))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private var casualtyCell: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.fg2)
            Text(state.casualtyId)
                .tccc(.timer)
                .foregroundStyle(palette.fg)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 78)
    }

    private var gpsCell: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.fg2)
            Text(formattedGps)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.fg1)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattedGps: String {
        let lat = String(format: "%.4f° N", state.gpsLatitude)
        let lon = String(format: "%.4f° E", state.gpsLongitude)
        return "\(lat)  \(lon)"
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
