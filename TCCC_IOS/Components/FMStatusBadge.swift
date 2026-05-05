import SwiftUI
import FoundationModels

/// Persistent compact badge showing the live availability of the Apple
/// Foundation Model. Replaces the one-shot error banner pattern that was
/// confusing operators after the model finished downloading: tapping
/// "Generate" still showed the stale error until the screen was
/// re-entered. With this badge, the UI shows current truth on a
/// 5-second tick.
///
/// States rendered:
///   - SLM · READY        (green)        → Generate buttons are tappable
///   - SLM · DOWNLOADING  (warn / amber) → still pulling weights
///   - SLM · OFF          (warn)         → Apple Intelligence disabled
///   - SLM · UNSUPPORTED  (crit)         → device doesn't support FM
///
/// Per night-pass A5.
struct FMStatusBadge: View {
    @Environment(\.palette) private var palette
    @State private var availability: SystemLanguageModel.Availability =
        SystemLanguageModel.default.availability

    /// 5s tick — Foundation Model availability changes are infrequent
    /// (download progress is the main one) so polling at this rate is
    /// generous without burning a Timer.
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
        .onReceive(tick) { _ in
            availability = SystemLanguageModel.default.availability
        }
    }

    /// True iff Generate buttons should be enabled. Reads cleanly from
    /// the same availability snapshot the badge displays so the UI stays
    /// consistent.
    static func isReady() -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    private var label: String {
        switch availability {
        case .available:
            return "SLM · ready"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:           return "SLM · unsupported"
            case .appleIntelligenceNotEnabled: return "SLM · off"
            case .modelNotReady:               return "SLM · downloading"
            @unknown default:                  return "SLM · n/a"
            }
        @unknown default:
            return "SLM · n/a"
        }
    }

    private var dotColor: Color {
        switch availability {
        case .available:
            return palette.ok
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:           return palette.crit
            case .appleIntelligenceNotEnabled: return palette.warn
            case .modelNotReady:               return palette.warn
            @unknown default:                  return palette.fg3
            }
        @unknown default:
            return palette.fg3
        }
    }
}
