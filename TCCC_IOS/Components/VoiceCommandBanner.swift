import SwiftUI

/// Top-positioned auto-fire banner for voice commands ("new patient",
/// "end encounter"). Detected in the committed transcript line by
/// `AppState.detectVoiceCommand`, armed via `armVoiceCommand`, and
/// rendered here for ~2s with a tap-anywhere-to-cancel scrim.
///
/// Control polarity is intentionally OPPOSITE of `ConfirmationBanner`:
/// that one demands a YES tap, this one auto-fires unless the operator
/// taps to cancel. Voice commands are issued mid-task with hands dirty;
/// requiring a confirm tap defeats the purpose. The 2s pause + the
/// rare-phrase trigger together provide the safety margin.
struct VoiceCommandBanner: View {
    let state: AppState
    @Environment(\.palette) private var palette

    /// Tick state — refreshed by a 50ms timer so the countdown text
    /// re-renders smoothly. SwiftUI doesn't observe `Date()` calls
    /// directly, so we keep an explicit `nowTick`.
    @State private var nowTick = Date()
    @State private var ticker: Timer?

    var body: some View {
        if let pending = state.pendingVoiceCommand {
            ZStack(alignment: .top) {
                scrim
                bannerCard(for: pending)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .transition(.opacity)
            .onAppear {
                Haptics.notify(.warning)
                nowTick = Date()
                ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    Task { @MainActor in
                        nowTick = Date()
                    }
                }
            }
            .onDisappear {
                ticker?.invalidate()
                ticker = nil
            }
        }
    }

    private var scrim: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .onTapGesture { state.cancelVoiceCommand() }
    }

    private func bannerCard(for pending: AppState.PendingVoiceCommand) -> some View {
        let remaining = max(0, pending.firesAt.timeIntervalSince(nowTick))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(pending.command.bannerTitle)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.crit)
                Spacer(minLength: 12)
                Text(String(format: "%.1f s", remaining))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.fg)
                    .monospacedDigit()
            }
            Text(pending.command.bannerDetail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap anywhere to cancel")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(palette.fg2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .strokeBorder(palette.crit, lineWidth: 2)
        )
    }
}

extension AppState.VoiceCommand {
    fileprivate var bannerTitle: String {
        switch self {
        case .newPatient:   "New Patient"
        case .endEncounter: "End Encounter"
        }
    }

    fileprivate var bannerDetail: String {
        switch self {
        case .newPatient:
            "Voice command detected. Casualty will be archived and a new ID assigned."
        case .endEncounter:
            "Voice command detected. Current casualty's care will be marked complete."
        }
    }
}
