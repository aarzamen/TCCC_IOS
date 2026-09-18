import Foundation
import AVFoundation
import TCCCDomain

/// Owned by the serial audio consumer, never shared with the render callback.
/// iOS AGC is preferred; the bounded software controller is the fallback.
struct MicrophoneInputProcessor {
    struct Report: Sendable {
        let rms: Float
        let gainDb: Float
        let mode: MicrophoneGainMode
        let shouldPublish: Bool
    }

    private var controller: AutomaticMicrophoneGain
    private var secondsSincePublication: Double = 1

    init(mode: MicrophoneGainMode = .softwareAutomatic) {
        controller = AutomaticMicrophoneGain(mode: mode)
    }

    static func configured(for input: AVAudioInputNode) -> Self {
        do {
            try input.setVoiceProcessingEnabled(true)
            input.isVoiceProcessingAGCEnabled = true
        } catch {
            // The software fallback below is explicit and visible in Settings.
        }
        let enabled = input.isVoiceProcessingEnabled && input.isVoiceProcessingAGCEnabled
            && !input.isVoiceProcessingBypassed
        return Self(mode: enabled ? .systemAutomatic : .softwareAutomatic)
    }

    mutating func process(_ buffer: AVAudioPCMBuffer) -> Report {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let interleaved = buffer.format.isInterleaved
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var energy: Double = 0
        var peak: Float = 0
        var samples = 0
        for audio in buffers {
            guard let bytes = audio.mData else { continue }
            let count = frames * (interleaved ? channels : 1)
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                let data = bytes.assumingMemoryBound(to: Float.self)
                for index in 0..<count {
                    let value = data[index].isFinite ? data[index] : 0
                    data[index] = value
                    energy += Double(value) * Double(value)
                    peak = max(peak, abs(value))
                }
                samples += count
            case .pcmFormatInt16:
                let data = bytes.assumingMemoryBound(to: Int16.self)
                for index in 0..<count {
                    let value = Float(data[index]) / 32768
                    energy += Double(value) * Double(value)
                    peak = max(peak, abs(value))
                }
                samples += count
            default:
                break // Engine and converter paths supply Float32 or Int16 PCM.
            }
        }
        let duration = buffer.format.sampleRate > 0 ? Double(frames) / buffer.format.sampleRate : 0
        let rms = samples > 0 ? Float(sqrt(energy / Double(samples))) : 0
        let gain = controller.gain(rms: rms, peak: peak, duration: duration)
        for audio in buffers {
            guard let bytes = audio.mData else { continue }
            let count = frames * (interleaved ? channels : 1)
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                let data = bytes.assumingMemoryBound(to: Float.self)
                for index in 0..<count { data[index] = max(-0.89, min(0.89, data[index] * gain)) }
            case .pcmFormatInt16:
                let data = bytes.assumingMemoryBound(to: Int16.self)
                for index in 0..<count {
                    let value = max(-0.89, min(0.89, Float(data[index]) / 32768 * gain))
                    data[index] = Int16(value * 32768)
                }
            default:
                break
            }
        }
        secondsSincePublication += duration
        let shouldPublish = secondsSincePublication >= 0.1
        if shouldPublish { secondsSincePublication = 0 }
        return Report(rms: rms * gain, gainDb: controller.gainDb, mode: controller.mode,
                      shouldPublish: shouldPublish)
    }
}
