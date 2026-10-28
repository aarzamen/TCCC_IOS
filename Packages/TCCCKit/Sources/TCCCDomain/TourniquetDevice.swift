import Foundation

/// Tourniquet devices a medic may name aloud, for the DD 1380 tourniquet
/// "TYPE" boxes (DD Form 1380 instructions, JUL 2025: "write type of tourniquet
/// used"). A device is recognised only when it is named; it is never guessed
/// from context. Patterns include common speech-recognition spellings
/// ("cat tonic", "soft t").
public enum TourniquetDevice {

    public struct Device: Sendable, Equatable {
        public let name: String
        public let isJunctional: Bool
    }

    // Order matters: junctional SAM before SAM XT. Case-insensitive.
    private static let catalogue: [(name: String, junctional: Bool, pattern: String)] = [
        ("CAT", false, #"\bcat\b(?!\s+scan)|combat application tourniquet"#),
        ("SOFTT-W", false, #"\bsoft\s*-?\s*t(?:\s*-?\s*w(?:ide)?)?\b|\bsoftt\b"#),
        ("SAM-JT", true, #"\bsjt\b|\bsam\s*-?\s*jt\b|\bsam\s+junctional"#),
        ("SAM XT", false, #"\bsam\s*-?\s*xt\b"#),
        ("TMT", false, #"\btmt\b|tactical mechanical tourniquet"#),
        ("RMT", false, #"\brmt\b|ratcheting medical tourniquet"#),
        ("EMT", false, #"\bemt\s+(?:tourniquet|tq)\b|emergency\s+(?:and|&)\s+military\s+tourniquet"#),
        ("JETT", true, #"\bjett\b|junctional emergency treatment tool"#),
        ("CRoC", true, #"\bcroc\b|combat ready clamp"#),
        ("AAJT", true, #"\baajt\b|abdominal aortic\s+(?:and|&)\s+junctional tourniquet"#),
    ]

    private static let compiled: [(Device, NSRegularExpression)] = catalogue.map {
        (Device(name: $0.name, isJunctional: $0.junctional),
         try! NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]))
    }

    /// The first device named in `text`, or nil when none is named.
    public static func named(in text: String) -> Device? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return compiled.first { $0.1.firstMatch(in: text, range: range) != nil }?.0
    }

    /// The engine's intervention description: "Tourniquet applied", plus the
    /// device in parentheses when one was named.
    public static func appliedDescription(device: Device?) -> String {
        device.map { "Tourniquet applied (\($0.name))" } ?? "Tourniquet applied"
    }
}
