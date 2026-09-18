import AVFoundation
import Foundation

/// Owned by the capture actor. Both processing and archiving consume the same
/// converted 16 kHz mono PCM; errors propagate to the capture's terminal status.
final class PCMArchiveWriter {
    private let converter: ParakeetPCMResampler
    private let audioFile: AVAudioFile

    init(inputFormat: AVAudioFormat, audioFile: AVAudioFile) throws {
        guard let converter = ParakeetPCMResampler(inputFormat: inputFormat),
              audioFile.processingFormat.isEqual(ParakeetPCMResampler.outputFormat) else {
            throw CaptureError.unsupportedFormat
        }
        self.converter = converter
        self.audioFile = audioFile
    }

    func append(_ buffer: AVAudioPCMBuffer,
                process: (AVAudioPCMBuffer) -> Void = { _ in }) throws {
        let converted = try converter.convert(buffer)
        guard converted.frameLength > 0 else { return }
        process(converted)
        try audioFile.write(from: converted)
    }

    private enum CaptureError: LocalizedError {
        case unsupportedFormat
        var errorDescription: String? { "Could not prepare 16 kHz mono audio capture" }
    }
}
