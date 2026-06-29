import Foundation

enum PartialCommitGate {
    static func committableText(scheduled: String, latest: String) -> String? {
        let candidate = scheduled.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        let current = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        if current == candidate { return candidate }
        guard current.hasPrefix(candidate) else { return nil }

        let boundary = current.index(current.startIndex, offsetBy: candidate.count)
        guard boundary == current.endIndex || isTokenBoundary(current[boundary]) else {
            return nil
        }
        return candidate
    }

    private static func isTokenBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.punctuationCharacters.contains($0)
        }
    }
}
