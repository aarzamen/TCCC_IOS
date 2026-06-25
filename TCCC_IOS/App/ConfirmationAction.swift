import Foundation

/// Lifecycle actions that need a confirmation step before firing.
enum ConfirmationAction: Identifiable, Sendable {
    case newPatient
    case endCare
    case wipe

    var id: String {
        switch self {
        case .newPatient: return "new"
        case .endCare:    return "end"
        case .wipe:       return "wipe"
        }
    }

    var headline: String {
        switch self {
        case .newPatient: return "START NEW CASUALTY"
        case .endCare:    return "END CARE FOR THIS CASUALTY?"
        case .wipe:       return "WIPE ALL CASUALTY DATA"
        }
    }

    var detail: String {
        switch self {
        case .newPatient:
            return "Increment casualty ID, clear current state. Operator profile preserved."
        case .endCare:
            return "Mark current casualty handed off, clear screen for next assignment. Casualty counter not incremented."
        case .wipe:
            return "Erase all transcripts, vitals, exports, and SLM output. Reset to factory state. This cannot be undone."
        }
    }

    var confirmLabel: String {
        switch self {
        case .newPatient: return "Yes, new"
        case .endCare:    return "Yes, end"
        case .wipe:       return "Yes, wipe"
        }
    }

    /// Whether the confirmation should style itself as destructive (red).
    var isDestructive: Bool {
        switch self {
        case .wipe:       return true
        default:          return false
        }
    }
}
