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
            return "Archive this casualty's record and open a new one. Operator profile preserved."
        case .endCare:
            return "Archive this casualty's record and mark care complete. Casualty counter not incremented."
        case .wipe:
            return "Permanently purge ALL archived casualties, transcripts, vitals, and exports. This cannot be undone."
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
