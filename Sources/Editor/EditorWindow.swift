import AppKit
import SwiftUI

/// Owns one editor window and its document.
@MainActor
final class EditorWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: (EditorWindow) -> Void

    init(capture: Capture, onClose: @escaping (EditorWindow) -> Void) {
        self.onClose = onClose

        let doc = EditorDocument(capture: capture)
        let hosting = NSHostingController(rootView: EditorView(doc: doc))
        window = NSWindow(contentViewController: hosting)
        window.title = "Super Duper Screenshot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        let toolbarHeight: CGFloat = 44
        let visible = (capture.sourceScreen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = CGSize(
            width: min(capture.pointSize.width + 48, visible.width * 0.88),
            height: min(capture.pointSize.height + 48 + toolbarHeight, visible.height * 0.88)
        )
        window.setContentSize(CGSize(width: max(700, target.width), height: max(440, target.height)))
        window.center()

        super.init()
        window.delegate = self
        window.isReleasedWhenClosed = false

        ActivationPolicy.retain()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicy.release()
        onClose(self)
    }
}
