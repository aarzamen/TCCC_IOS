import SwiftUI

@main
struct TCCC_IOSApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            if GraniteAudioBenchmarkView.shouldRun {
                GraniteAudioBenchmarkView(state: state)
            } else {
                ContentView(state: state)
                    .task { await state.load() }
            }
        }
    }
}
