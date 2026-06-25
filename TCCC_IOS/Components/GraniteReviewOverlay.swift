import SwiftUI
import TCCCDomain

/// Operator review of queued Granite candidate facts. Accept routes through the
/// engine-mediated apply path; Reject is destructive (long-press). Conflicts show
/// the engine value (which holds) and require an explicit override. Presented as a
/// ZStack overlay like SettingsOverlay / QuickActionsSheet; tap-scrim dismisses.
struct GraniteReviewOverlay: View {
    let state: AppState   // AppState is a final @Observable class; mutate via the reference
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onTapGesture { state.reviewOpen = false }
            VStack(alignment: .leading, spacing: 8) {
                Text("GRANITE REVIEW · \(state.graniteReviewQueue.count) PENDING")
                    .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                    .foregroundStyle(palette.fg)
                if let conflict = state.lastConflictMessage {
                    Text(conflict)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.crit)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.graniteReviewQueue) { item in
                            reviewCard(item)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 520, alignment: .leading)
            .background(palette.bg1)
        }
    }

    private func reviewCard(_ item: GraniteReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(item.patch.candidateFacts) { fact in
                HStack(spacing: 10) {
                    Text("\(fact.field) = \(fact.value ?? "—")")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.fg)
                    Spacer()
                    if item.status == .readyForOperatorReview {
                        Button("ACCEPT") {
                            Task {
                                if let a = OperatorAcceptedFact(fact, from: item.validation) {
                                    await state.acceptGraniteFact(a, in: item)
                                }
                            }
                        }
                        .frame(minWidth: 64, minHeight: 44)   // gloved-hand
                    }
                }
            }
            HoldToConfirmButton(label: "Reject", systemImage: "xmark",
                                style: .standard, holdSeconds: 2.0) {
                state.rejectGraniteReviewItem(item)
            }
        }
        .padding(10)
        .background(palette.bg)
    }
}
