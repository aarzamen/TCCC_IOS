import Foundation

public enum MicrophoneGainMode: String, Sendable {
    case systemAutomatic
    case softwareAutomatic
}

/// Level control only; this makes no claim about speech or signal quality.
public struct AutomaticMicrophoneGain: Sendable {
    public let mode: MicrophoneGainMode
    public private(set) var gainDb: Float = 0
    private var linear: Float = 1

    public init(mode: MicrophoneGainMode) { self.mode = mode }

    public mutating func gain(rms: Float, peak: Float, duration: TimeInterval) -> Float {
        guard rms.isFinite, peak.isFinite, duration.isFinite,
              rms >= 0, peak >= 0, duration > 0 else {
            gainDb = -120
            linear = 1
            return 0
        }
        // The fallback is intentionally bounded: silence cannot wind it up,
        // speech rises slowly, and a loud arrival receives immediate headroom.
        let quiet = rms < 0.004
        let desired: Float = mode == .systemAutomatic || quiet
            ? 1 : min(4, max(0.0631, 0.1259 / max(rms, 0.00001)))
        if quiet { linear = min(linear, 1) }
        let timeConstant: Double = desired < linear ? 0.05 : 1.5
        let blend = Float(1 - exp(-min(duration, 1) / timeConstant))
        linear += (desired - linear) * blend
        let peakLimit: Float = peak > 0 ? min(4, 0.89 / peak) : 4
        linear = max(0, min(linear, peakLimit))
        gainDb = 20 * log10f(max(linear, 0.000001))
        return linear
    }
}
