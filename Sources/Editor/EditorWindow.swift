import AppKit
import Combine
import SwiftUI

/// Owns one editor window and its document.
@MainActor
final class EditorWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let doc: EditorDocument
    private let onClose: (EditorWindow) -> Void
    private var closeApproved = false
    private var dirtyObserver: AnyCancellable?

    /// Top-left point the next editor window cascades from, so a second
    /// editor doesn't land exactly on top of the first.
    private static var cascadePoint = CGPoint.zero

    /// Forget the cascade position once every editor is closed, so the next
    /// one is centered again instead of drifting down-right forever.
    static func resetCascade() {
        cascadePoint = .zero
    }

    var hasUnsavedChanges: Bool { doc.hasUnsavedChanges }

    /// Pass `document` to adopt annotations made elsewhere (screen draw mode);
    /// otherwise a fresh document is created from the capture.
    init(capture: Capture, document: EditorDocument? = nil, onClose: @escaping (EditorWindow) -> Void) {
        self.onClose = onClose

        let doc = document ?? EditorDocument(capture: capture)
        self.doc = doc
        let hosting = NSHostingController(rootView: EditorView(doc: doc))
        window = NSWindow(contentViewController: hosting)
        window.title = "Nice Shot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        let ribbonOn = UserDefaults.standard.object(forKey: "editorRibbon") as? Bool ?? true
        let toolbarHeight: CGFloat = ribbonOn ? 100 : 44
        let visible = (capture.sourceScreen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = CGSize(
            width: min(capture.pointSize.width + 48, visible.width * 0.88),
            height: min(capture.pointSize.height + 48 + toolbarHeight, visible.height * 0.88)
        )
        window.setContentSize(CGSize(width: max(700, target.width), height: max(440, target.height)))
        window.center()
        Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)

        super.init()
        window.delegate = self
        window.isReleasedWhenClosed = false

        // The title-bar "edited" dot mirrors whether closing would lose work.
        dirtyObserver = doc.$changeToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.window.isDocumentEdited = self.doc.hasUnsavedChanges
            }

        ActivationPolicy.retain()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Closing

    /// Unsaved annotations get the standard Save / Don't Save / Cancel sheet
    /// instead of vanishing on ⌘W.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closeApproved, doc.hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Save your annotations before closing?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                if self.doc.saveFlattened() { self.forceClose() }
            case .alertThirdButtonReturn:
                self.forceClose()
            default:
                break
            }
        }
        return false
    }

    /// Close without the unsaved-changes prompt (the user already decided).
    func forceClose() {
        closeApproved = true
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        dirtyObserver = nil
        ActivationPolicy.release()
        onClose(self)
    }
}
