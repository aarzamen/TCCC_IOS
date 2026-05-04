import Foundation

/// A single chronological intervention.
///
/// In the Python prototype (`state.py:312`) interventions are stored as
/// untyped strings inside `patient.interventions: list`. This Swift mirror
/// keeps the descriptor string but adds an `id`, a structured `kind`, and a
/// `timestamp` so the UI layer can render and order them deterministically.
public struct Intervention: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let kind: InterventionKind
    public let description: String

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: InterventionKind,
        description: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.description = description
    }
}
