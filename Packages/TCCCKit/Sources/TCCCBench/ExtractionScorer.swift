import Foundation

public struct FieldExpectation: Sendable, Codable, Equatable {
    public enum Mode: String, Codable, Sendable {
        case exact
        case contains
    }

    public let key: String
    public let expected: String
    public let mode: Mode

    public init(key: String, expected: String, mode: Mode) {
        self.key = key
        self.expected = expected
        self.mode = mode
    }
}

public struct ExtractionScore: Sendable, Codable, Equatable {
    public struct FieldResult: Sendable, Codable, Equatable {
        public let key: String
        public let expected: String
        public let actual: String?
        public let passed: Bool
    }

    public let fields: [FieldResult]
    public var passedCount: Int { fields.filter(\.passed).count }
    public var recall: Double {
        fields.isEmpty ? 0.0 : Double(passedCount) / Double(fields.count)
    }

    public init(fields: [FieldResult]) {
        self.fields = fields
    }
}

/// Ties ASR quality to the deliverable: after the engine ingests the
/// hypothesis transcript, did the DD1380-bound fields come out right?
/// Case-insensitive; `contains` = actual contains expected.
public enum ExtractionScorer {
    public static func score(
        expectations: [FieldExpectation],
        actual: [String: String]
    ) -> ExtractionScore {
        let fields = expectations.map { exp -> ExtractionScore.FieldResult in
            let actualValue = actual[exp.key]
            let passed: Bool
            switch (actualValue, exp.mode) {
            case (nil, _):
                passed = false
            case (let value?, .exact):
                passed = value.lowercased() == exp.expected.lowercased()
            case (let value?, .contains):
                passed = value.lowercased().contains(exp.expected.lowercased())
            }
            return .init(key: exp.key, expected: exp.expected, actual: actualValue, passed: passed)
        }
        return ExtractionScore(fields: fields)
    }
}
