import SwiftUI

/// Persistent compact badge showing the live availability of the
/// currently-selected on-device LLM backend (Apple Foundation Models,
/// LFM2.5, Qwen 3, or Granite). Replaces the one-shot error banner pattern that
/// was confusing operators after the model finished downloading: tapping
/// "Generate" still showed the stale error until the screen was
/// re-entered. With this badge, the UI shows current truth on a
/// 5-second tick and re-reads immediately when the operator switches
/// backends in Settings.
///
/// States rendered (label uses the short-form backend prefix):
///   - <BACKEND> · READY          (ok)    → Generate buttons are tappable
///   - <BACKEND> · DOWNLOADING    (warn)  → still pulling weights
///   - <BACKEND> · NOT PROVIDED   (warn)  → operator must download/import
///   - <BACKEND> · OFF            (warn)  → backend disabled
///   - <BACKEND> · UNSUPPORTED    (crit)  → device not eligible
///   - <BACKEND> · N/A            (fg3)   → unknown
///
/// Per night-pass A5; backend-aware update 2026-05-05.
struct FMStatusBadge: View {
    let state: AppState

    @Environment(\.palette) private var palette
    @State private var availability: BackendAvailability = .unknown

    /// 5s tick — backend availability changes are infrequent (download
    /// progress is the main one) so polling at this rate is generous
    /// without burning a Timer.
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
        .task(id: state.llmBackend) {
            // Re-read immediately when the operator switches backends in
            // Settings so the badge doesn't lag behind the selection.
            availability = await state.currentBackend.availability
        }
        .onReceive(tick) { _ in
            Task { @MainActor in
                availability = await state.currentBackend.availability
            }
        }
    }

    /// Short-form prefix used in the badge label. Mapped from the
    /// backend's `displayName` rather than parsed at runtime — the
    /// long names ("Apple Foundation Models", "Liquid LFM2.5 1.2B",
    /// "Qwen 3 1.7B") would not fit the 10pt heavy-tracked badge.
    private var prefix: String {
        switch state.llmBackend {
        case .appleFoundation: return "FM"
        case .lfm2:            return "LFM2"
        case .qwen3:           return "QWEN"
        case .graniteText:     return "GRANITE"
        }
    }

    private var label: String {
        let suffix: String
        switch availability {
        case .available:        suffix = "ready"
        case .downloading:      suffix = "downloading"
        case .modelNotProvided: suffix = "not provided"
        case .deviceNotEligible: suffix = "unsupported"
        case .disabled:         suffix = "off"
        case .unknown:          suffix = "n/a"
        }
        return "\(prefix) · \(suffix)"
    }

    private var dotColor: Color {
        switch availability {
        case .available:         return palette.ok
        case .downloading:       return palette.warn
        case .modelNotProvided:  return palette.warn
        case .deviceNotEligible: return palette.crit
        case .disabled:          return palette.warn
        case .unknown:           return palette.fg3
        }
    }
}
