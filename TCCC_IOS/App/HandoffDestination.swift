import Foundation

/// Transmit destinations available on the Handoff screen.
///
/// All four are visual targets only — no networking framework is wired up
/// (RF Ghost). The QR option is the one with a real local rendering path:
/// `CIQRCodeGenerator` produces an offline image of the patient's encoded
/// JSON, which the medic shows to the receiving Role-2 device.
enum HandoffDestination: String, CaseIterable, Sendable {
    case atak
    case medhub
    case qr
    case nfc

    var displayName: String {
        switch self {
        case .atak:   "ATAK"
        case .medhub: "MEDHUB"
        case .qr:     "QR · OFFLINE"
        case .nfc:    "NFC TAP"
        }
    }

    var symbol: String {
        switch self {
        case .atak:   "network"
        case .medhub: "paperplane"
        case .qr:     "qrcode"
        case .nfc:    "wave.3.right"
        }
    }

    /// True when this destination has a real implementation that actually
    /// moves data off-device. False = visual placeholder (RF Ghost: no networking
    /// framework wired). Selecting a non-functional destination MUST NOT log a
    /// success-shaped TRANSMIT line.
    var isFunctional: Bool {
        switch self {
        case .qr: true
        case .atak, .medhub, .nfc: false
        }
    }
}
