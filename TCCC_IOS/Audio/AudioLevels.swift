import Foundation
import Observation
import TCCCDomain

@MainActor
@Observable
final class AudioLevels {
    static let barCount: Int = 32

    private(set) var current: Float = 0
    private(set) var bars: [Float] = Array(repeating: 0, count: AudioLevels.barCount)

    private(set) var gainMode: MicrophoneGainMode?
    private(set) var gainDb: Float = 0

    func ingest(_ report: MicrophoneInputProcessor.Report) {
        gainMode = report.mode
        gainDb = report.gainDb
        ingest(report.rms)
    }

    func ingest(_ rms: Float) {
        // Audio amplitude is logarithmic. Voice RMS lives roughly in
        // [1e-4, 0.3]. Convert to dBFS, clamp to a -50 dB → 0 dB visible
        // range, normalize to 0...1. This makes normal speech fill the
        // bars rather than barely nudging them.
        let safe = max(rms, 1e-5)
        let dB = 20 * log10f(safe)
        let normalized = max(0, min(1, (dB + 50) / 50))
        current = normalized
        bars.removeFirst()
        bars.append(normalized)
    }

    func reset() {
        gainMode = nil
        gainDb = 0
        current = 0
        bars = Array(repeating: 0, count: AudioLevels.barCount)
    }
}
