import Foundation

struct TranscriptLine: Identifiable, Hashable, Sendable {
    enum Speaker: String, Sendable {
        case medic
        case casualty
        case system
    }

    let id: UUID
    let speaker: Speaker
    let text: String
    let timestamp: Date
    var isPartial: Bool

    init(
        id: UUID = UUID(),
        speaker: Speaker = .medic,
        text: String,
        timestamp: Date = Date(),
        isPartial: Bool = false
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
        self.isPartial = isPartial
    }
}

extension TranscriptLine {
    var displayTimestamp: String {
        let formatter = DateFormatter.transcriptTime
        return formatter.string(from: timestamp)
    }
}

extension DateFormatter {
    static let transcriptTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
