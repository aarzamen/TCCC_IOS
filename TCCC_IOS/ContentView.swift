import SwiftUI

struct ContentView: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            palette.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StatusStrip(state: state)
                ScreenPager(state: state)
                    .frame(maxHeight: .infinity)
            }
        }
        .preferredColorScheme(state.theme.preferredColorScheme)
        .environment(\.palette, state.theme.palette)
        .ignoresSafeArea(.keyboard)
    }
}

#Preview {
    ContentView(state: AppState())
        .previewInterfaceOrientation(.landscapeLeft)
}
