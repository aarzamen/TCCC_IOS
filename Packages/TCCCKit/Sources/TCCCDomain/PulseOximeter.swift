import Foundation

/// Availability of decoded measurements, without inferring unverified signal flags.
public enum PulseOximeterQuality: String, Sendable, Codable {
    case unknown
    case unavailable
    case unsupportedEncoding
}

/// A consumer-sensor observation with its original frame and receipt provenance.
public struct PulseOximeterReading: Sendable, Codable, Equatable {
    public let id: UUID
    public let receivedAt: Date
    public let acquiredAt: Date?
    public let spo2: Int?
    public let pulseRate: Int?
    public let perfusionIndex: Double?
    public let rawFrame: Data
    public let protocolVersion: String
    public let quality: PulseOximeterQuality

    public init(
        id: UUID = UUID(),
        receivedAt: Date,
        acquiredAt: Date? = nil,
        spo2: Int?,
        pulseRate: Int?,
        perfusionIndex: Double?,
        rawFrame: Data,
        protocolVersion: String = "lepu-s5w-observed-v1",
        quality: PulseOximeterQuality = .unknown
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.acquiredAt = acquiredAt
        self.spo2 = spo2
        self.pulseRate = pulseRate
        self.perfusionIndex = perfusionIndex
        self.rawFrame = rawFrame
        self.protocolVersion = protocolVersion
        self.quality = quality
    }
}

/// Amplitude samples with flag bits preserved in the original frame.
public struct PulseOximeterWaveform: Sendable, Codable, Equatable {
    public let receivedAt: Date
    public let rawFrame: Data
    public let samples: [UInt8]

    public init(receivedAt: Date, rawFrame: Data, samples: [UInt8]) {
        self.receivedAt = receivedAt
        self.rawFrame = rawFrame
        self.samples = samples
    }
}

/// Checksum-valid auxiliary evidence whose payload meaning is not verified.
public struct PulseOximeterRawFrame: Sendable, Codable, Equatable {
    public let receivedAt: Date
    public let rawFrame: Data

    public init(receivedAt: Date, rawFrame: Data) {
        self.receivedAt = receivedAt
        self.rawFrame = rawFrame
    }
}

/// A checksum-valid packet; unrecognized types retain their original evidence.
public enum PulseOximeterPacket: Sendable, Codable, Equatable {
    case reading(PulseOximeterReading)
    case waveform(PulseOximeterWaveform)
    case unknown(rawFrame: Data, receivedAt: Date)
}

/// Incremental decoder for the observed S5W AA55 stream, independent of transport.
public struct LepuPulseOximeterDecoder: Sendable {
    private struct ReceivedByte: Sendable {
        let value: UInt8
        let receivedAt: Date
    }

    private var buffer: [ReceivedByte] = []

    public init() {
        buffer.reserveCapacity(259)
    }

    /// Receipt time belongs to the notification that completes each frame.
    /// Retained partial input is bounded by the one-byte length field (259 bytes).
    public mutating func append(_ data: Data, receivedAt: Date) -> [PulseOximeterPacket] {
        var packets: [PulseOximeterPacket] = []
        // Consume incrementally so even a very large noisy notification cannot
        // grow retained parser state beyond one maximum-length frame.
        for byte in data {
            buffer.append(ReceivedByte(value: byte, receivedAt: receivedAt))
            while !buffer.isEmpty {
                guard buffer[0].value == 0xAA else {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= 2 else { break }
                guard buffer[1].value == 0x55 else {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= 5 else { break }
                let length = Int(buffer[3].value) + 4
                let type = buffer[4].value
                // Known types have fixed observed shapes. Do not wait for a
                // corrupted length or decode a shorter payload at known offsets.
                guard length >= 6,
                      type != 1 || length == 12,
                      type != 2 || length == 11 else {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= length else { break }
                let frame = buffer.prefix(length).map(\.value)
                guard Self.crc8Maxim(frame) == 0 else {
                    // Shift only one byte: a valid sync may exist inside the
                    // rejected candidate, including after a corrupt length.
                    buffer.removeFirst()
                    continue
                }
                // A corrupt unknown-length prefix can delay parsing of an
                // already-received frame. Retain its actual completion receipt.
                let frameReceivedAt = buffer[length - 1].receivedAt
                buffer.removeFirst(length)
                packets.append(Self.packet(from: frame, receivedAt: frameReceivedAt))
            }
        }
        return packets
    }

    /// Discard partial bytes when a connection or stream changes.
    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    private static func packet(from frame: [UInt8], receivedAt: Date) -> PulseOximeterPacket {
        let rawFrame = Data(frame)
        switch frame[4] {
        case 1:
            guard frame[7] == 0 else {
                return .reading(PulseOximeterReading(
                    receivedAt: receivedAt,
                    spo2: nil,
                    pulseRate: nil,
                    perfusionIndex: nil,
                    rawFrame: rawFrame,
                    quality: .unsupportedEncoding
                ))
            }
            let spo2 = (1...100).contains(frame[5]) ? Int(frame[5]) : nil
            let pulseRate = frame[6] > 0 ? Int(frame[6]) : nil
            let perfusionIndex = frame[8] > 0 ? Double(frame[8]) / 10 : nil
            return .reading(PulseOximeterReading(
                receivedAt: receivedAt,
                spo2: spo2,
                pulseRate: pulseRate,
                perfusionIndex: perfusionIndex,
                rawFrame: rawFrame,
                quality: spo2 == nil || pulseRate == nil ? .unavailable : .unknown
            ))
        case 2:
            return .waveform(PulseOximeterWaveform(
                receivedAt: receivedAt,
                rawFrame: rawFrame,
                samples: frame[5..<(frame.count - 1)].map { $0 & 0x7F }
            ))
        default:
            return .unknown(rawFrame: rawFrame, receivedAt: receivedAt)
        }
    }

    // CRC-8/MAXIM-DOW: reflected polynomial 0x8C, initial value and xor-out 0.
    // A complete valid frame, including its checksum byte, has remainder zero.
    static func crc8Maxim(_ bytes: [UInt8]) -> UInt8 {
        var remainder: UInt8 = 0
        for byte in bytes {
            remainder ^= byte
            for _ in 0..<8 {
                remainder = remainder & 1 == 1 ? (remainder >> 1) ^ 0x8C : remainder >> 1
            }
        }
        return remainder
    }
}
