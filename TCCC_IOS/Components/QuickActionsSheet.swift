import SwiftUI

struct QuickActionsSheet: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    state.quickActionsOpen = false
                }

            sheet
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            grid
        }
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .strokeBorder(palette.lineStrong, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("Quick Actions")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(palette.fg2)

            Spacer(minLength: 0)

            Button {
                state.quickActionsOpen = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("Close")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.6)
                        .textCase(.uppercase)
                }
                .foregroundStyle(palette.fg)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .overlay(
                    Rectangle()
                        .strokeBorder(palette.line, lineWidth: Layout.hairline)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.lineStrong)
                .frame(height: Layout.hairline)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Layout.hairline), count: 3),
            spacing: Layout.hairline
        ) {
            actionButton(label: "Mark Time", sub: "Stamp now", icon: "bookmark.fill") {
                state.appendSystem("MARK · \(Self.timestamp())")
                state.quickActionsOpen = false
            }
            actionButton(label: "New Vital", sub: "Dictate", icon: "heart.text.square") {
                state.appendSystem("VITALS · pending dictation")
                state.quickActionsOpen = false
            }
            actionButton(label: "TQ Apply", sub: "Log TQ", icon: "bandage.fill") {
                state.appendSystem("TQ APPLIED · pending location")
                state.quickActionsOpen = false
            }
            actionButton(label: "Med Given", sub: "Pick + dose", icon: "syringe.fill") {
                state.appendSystem("MED GIVEN · pending dose")
                state.quickActionsOpen = false
            }
            actionButton(label: "Photo", sub: "Wound", icon: "camera.fill") {
                state.appendSystem("PHOTO · capture deferred")
                state.quickActionsOpen = false
            }
            actionButton(label: "End Care", sub: "Finalize \(state.casualtyId)", icon: "checkmark.shield.fill") {
                Task { @MainActor in await state.endCurrentCare() }
                state.quickActionsOpen = false
            }
        }
        .background(palette.line)
    }

    private func actionButton(
        label: String,
        sub: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(palette.accent)
                Text(label)
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
                Text(sub)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.fg2)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(palette.bg1)
        }
        .buttonStyle(.plain)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
