import SwiftUI

@main
struct TCCC_IOSApp: App {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if GraniteAudioBenchmarkView.shouldRun {
                GraniteAudioBenchmarkView(state: state)
            } else if TranscriptionBenchmarkView.shouldRun {
                TranscriptionBenchmarkView()
            } else {
                ContentView(state: state)
                    .task {
                        await state.load()
                        state.startWirelessSensorsIfNeeded()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        guard state.wirelessSensors.configured else { return }
                        if phase == .active { state.wirelessSensors.transport.applicationDidBecomeActive() }
                        if phase == .background { state.wirelessSensors.transport.applicationDidEnterBackground() }
                    }
            }
        }
    }
}
