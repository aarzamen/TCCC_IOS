import Foundation
import TCCCDomain

/// A coarse display of the recorded hemorrhage location, never a wound coordinate
/// or an inferred treatment site. Unknown and ambiguous text stays visible.
struct BodyMapPresentation: Sendable {
    enum Surface: Sendable { case front, back, unspecified }
    struct Region: Equatable, Sendable {
        let name: String
        /// Front-view coordinates in a 120 x 200 canvas. Back mirrors centerX.
        let centerX: Double
        let centerY: Double
        let width: Double
        let height: Double
    }
    let location: String?
    let intervention: String?
    var regions: [Region] = []
    var surface: Surface = .unspecified
    var placementNote = "Location not recorded"

    init(patient: PatientState?) {
        location = Self.nonblank(patient?.march.hemorrhageLocation)
        intervention = Self.nonblank(patient?.march.hemorrhageIntervention)
        guard let location else { return }
        let words = Set(location.lowercased().split { !$0.isLetter }.map(String.init))
        func has(_ options: String...) -> Bool { !words.isDisjoint(with: options) }

        let front = has("anterior", "front")
        let back = has("posterior", "back")
        let right = has("right", "rt")
        let left = has("left", "lt")
        let bilateral = has("bilateral", "both")
        guard !(front && back), !(right && left), !(bilateral && (right || left)) else {
            placementNote = "Location needs review"
            return
        }
        surface = front ? .front : (back ? .back : .unspecified)

        var sites: [Site] = []
        if has("head", "scalp", "forehead") { sites.append(.head) }
        if has("neck") { sites.append(.neck) }
        if has("chest", "thorax", "thoracic") { sites.append(.chest) }
        if has("abdomen", "abdominal") { sites.append(.abdomen) }
        if has("pelvis", "pelvic", "groin") { sites.append(.pelvis) }
        if has("forearm", "forearms") {
            sites.append(.forearm)
        }
        if has("arm", "arms") {
            sites.append(has("upper") ? .upperArm : (has("lower") ? .forearm : .arm))
        }
        if has("thigh", "thighs", "femur") { sites.append(.thigh) }
        if has("calf", "calves", "shin", "shins", "tibia") { sites.append(.lowerLeg) }
        if has("leg", "legs") {
            sites.append(has("upper") ? .thigh : (has("lower") ? .lowerLeg : .leg))
        }

        // Do not partially plot a mixed description by discarding an unsupported
        // named site. The recorded text is more useful than a misleading highlight.
        let unsupportedSite = has("hand", "hands", "foot", "feet", "knee", "knees", "elbow", "elbows", "shoulder", "shoulders", "wrist", "wrists", "ankle", "ankles", "finger", "fingers", "toe", "toes")
        let uniqueSites = Set(sites)
        guard uniqueSites.count == 1, !unsupportedSite, let site = uniqueSites.first else {
            placementNote = uniqueSites.count > 1 || (unsupportedSite && !sites.isEmpty)
                ? "Location needs review" : "Location not mapped"
            return
        }
        if site.isLimb && !right && !left && !bilateral {
            placementNote = "Side not recorded"
            return
        }

        if bilateral {
            regions = [site.region(side: .right), site.region(side: .left)]
        } else {
            regions = [site.region(side: right ? .right : (left ? .left : nil))]
        }
        placementNote = switch surface {
        case .front: "Front surface recorded"
        case .back: "Back surface recorded"
        case .unspecified: "Surface not recorded"
        }
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private enum Side { case right, left }

    private enum Site: Hashable {
        case head, neck, chest, abdomen, pelvis, upperArm, forearm, arm, thigh, lowerLeg, leg

        var isLimb: Bool {
            switch self {
            case .upperArm, .forearm, .arm, .thigh, .lowerLeg, .leg: true
            default: false
            }
        }

        func region(side: Side?) -> Region {
            let shape: (name: String, x: Double, y: Double, w: Double, h: Double) = switch self {
            case .head: ("Head", 60, 17, 20, 23)
            case .neck: ("Neck", 60, 33, 12, 12)
            case .chest: ("Chest", 60, 61, 34, 26)
            case .abdomen: ("Abdomen", 60, 87, 31, 24)
            case .pelvis: ("Pelvis", 60, 108, 36, 20)
            case .upperArm: ("Upper arm", 34, 61, 14, 30)
            case .forearm: ("Forearm", 26, 91, 12, 29)
            case .arm: ("Arm", 30, 77, 16, 61)
            case .thigh: ("Thigh", 48, 135, 20, 34)
            case .lowerLeg: ("Lower leg", 48, 171, 16, 37)
            case .leg: ("Leg", 48, 153, 22, 71)
            }
            let x: Double
            let width: Double
            if isLimb {
                x = side == .left ? 120 - shape.x : shape.x
                width = shape.w
            } else if let side {
                x = 60 + (side == .right ? -shape.w / 4 : shape.w / 4)
                width = shape.w / 2
            } else {
                x = shape.x
                width = shape.w
            }
            let prefix = side.map { $0 == .right ? "Right " : "Left " } ?? ""
            return Region(name: prefix + shape.name, centerX: x, centerY: shape.y, width: width, height: shape.h)
        }
    }
}
