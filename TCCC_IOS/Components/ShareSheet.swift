import SwiftUI
import UIKit

/// Tiny SwiftUI wrapper around UIActivityViewController for share-sheet
/// exports. Pass an array of `Any` items — URLs, strings, Data, UIImage, etc.
/// All sharing remains local — RF Ghost still applies; the user picks where
/// the file goes (Files, AirDrop, Save to Photos…) and the OS handles it.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
