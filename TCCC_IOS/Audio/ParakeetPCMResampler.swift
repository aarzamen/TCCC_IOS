import AVFoundation
import Foundation

/// Reuses converter history across microphone buffers. A tap buffer ends an
/// input batch, not the audio stream; endOfStream would permanently drain it.
final class ParakeetPCMResampler {
    static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000, channels: 1, interleaved: false)!

    private let converter: AVAudioConverter

    init?(inputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.outputFormat) else {
            return nil
        }
        self.converter = converter
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard input.format.isEqual(converter.inputFormat) else {
            throw ConversionFailure(reason: "Microphone format changed during Parakeet capture")
        }
        let ratio = Self.outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity) else {
            throw ConversionFailure(reason: "Could not allocate Parakeet resampling buffer")
        }
        guard input.frameLength > 0 else { return output }

        let batch = InputBatch(input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if let buffer = batch.take() {
                inputStatus.pointee = .haveData
                return buffer
            }
            inputStatus.pointee = .noDataNow
            return nil
        }
        if let conversionError { throw conversionError }
        guard status != .error else {
            throw ConversionFailure(reason: "Parakeet audio sample conversion failed")
        }
        return output
    }

    /// The converter callback may request input repeatedly within one call.
    /// Own the buffer and synchronize its one-use state without capturing a
    /// mutable local variable in an escaping callback.
    private final class InputBatch: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

        func take() -> AVAudioPCMBuffer? {
            lock.withLock {
                defer { buffer = nil }
                return buffer
            }
        }
    }

    private struct ConversionFailure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
}
