import Foundation

enum TranscriptBackend: String, Codable, Sendable, Equatable {
    case appleSpeech
    case parakeet
    case whisperKit
    case graniteSpeech
    case demo
}

enum TranscriptQualityFlag: String, Codable, Sendable, Equatable, Hashable {
    case duplicateCollapsed
    case clippedStart
    case clippedEnd
    case instructionLikeContent
    case lowConfidence
}

struct TranscriptSegment: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let startMs: Int
    let endMs: Int
    let textRaw: String
    var textNormalized: String
    let backend: TranscriptBackend
    let isFinal: Bool
    var qualityFlags: Set<TranscriptQualityFlag>
}

struct TranscriptSegmentLedger: Sendable, Equatable {
    private(set) var rawSegments: [TranscriptSegment] = []
    private(set) var normalizedSegments: [TranscriptSegment] = []

    mutating func appendRaw(
        text: String,
        startMs: Int,
        endMs: Int,
        backend: TranscriptBackend,
        isFinal: Bool
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var segment = TranscriptSegment(
            id: "seg-\(rawSegments.count + 1)",
            startMs: startMs,
            endMs: endMs,
            textRaw: trimmed,
            textNormalized: Self.normalize(trimmed),
            backend: backend,
            isFinal: isFinal,
            qualityFlags: []
        )

        if Self.looksInstructionLike(segment.textNormalized) {
            segment.qualityFlags.insert(.instructionLikeContent)
        }

        rawSegments.append(segment)

        if let last = normalizedSegments.last,
           last.textNormalized == segment.textNormalized {
            var merged = last
            merged.qualityFlags.formUnion(segment.qualityFlags)
            merged.qualityFlags.insert(.duplicateCollapsed)
            normalizedSegments[normalizedSegments.count - 1] = merged
        } else {
            normalizedSegments.append(segment)
        }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksInstructionLike(_ text: String) -> Bool {
        text.contains("ignore previous instructions")
            || text.contains("disregard previous")
            || text.contains("mark vitals normal")
            || text.contains("make vitals normal")
            || text.contains("fill out the form")
    }
}
