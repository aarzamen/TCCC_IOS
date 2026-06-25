import SwiftUI

@main
struct TCCC_IOSApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .task { await state.load() }
        }
    }
}
