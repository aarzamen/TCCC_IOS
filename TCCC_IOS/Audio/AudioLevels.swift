import Foundation
import Observation

@MainActor
@Observable
final class AudioLevels {
    static let barCount: Int = 32

    private(set) var current: Float = 0
    private(set) var bars: [Float] = Array(repeating: 0, count: AudioLevels.barCount)

    func ingest(_ rms: Float) {
        let normalized = max(0, min(1, rms * 6.5))
        current = normalized
        bars.removeFirst()
        bars.append(normalized)
    }

    func reset() {
        current = 0
        bars = Array(repeating: 0, count: AudioLevels.barCount)
    }
}
