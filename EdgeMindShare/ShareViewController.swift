import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share Extension entry point. Presents a small SwiftUI sheet, copies the shared
/// item into the App Group inbox, and opens `edgemindai://share/<id>`. No
/// inference or indexing runs here — iOS limits extensions to roughly 120 MB.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let host = UIHostingController(rootView: ShareSheetView(
            inputItems: items,
            onCancel: { [weak self] in self?.cancel() },
            onShare: { [weak self] payload in self?.finish(payload) }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: ShareExtensionError.cancelled)
    }

    private func finish(_ payload: SharePayload) {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        // Opening the app is best-effort; the inbox item is already persisted.
        if let url = URL(string: "edgemindai://share/\(payload.id.uuidString)") {
            openURL(url)
        }
    }

    /// Extensions may not use `UIApplication.open`; walk the responder chain to
    /// the host application instead.
    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}

enum ShareExtensionError: LocalizedError {
    case cancelled

    var errorDescription: String? { "Share cancelled." }
}
