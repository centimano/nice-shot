import AppKit
import ScreenCaptureKit

/// Orchestrates the whole capture flow: permission check → overlay/HUD →
/// ScreenCaptureKit capture → post-capture panel → editor.
@MainActor
final class CaptureCoordinator {
    private var overlay: SelectionOverlayController?
    private var panels: [PostCapturePanel] = []
    private var countdown: CountdownHUD?
    private var editors: [EditorWindow] = []

    // MARK: - Entry points

    func captureRegion() {
        guard ensurePermission(), overlay == nil else { return }
        let controller = SelectionOverlayController(mode: .region)
        overlay = controller
        controller.begin { [weak self] result in self?.handleOverlay(result) }
    }

    func captureWindow() {
        guard ensurePermission(), overlay == nil else { return }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let myPID = ProcessInfo.processInfo.processIdentifier
                let windows = content.windows.filter { w in
                    w.isOnScreen
                        && w.windowLayer == 0
                        && w.frame.width > 40 && w.frame.height > 40
                        && w.owningApplication?.processID != myPID
                }
                guard self.overlay == nil else { return }
                let controller = SelectionOverlayController(mode: .window, windows: windows)
                self.overlay = controller
                controller.begin { [weak self] result in self?.handleOverlay(result) }
            } catch {
                self.showError(error)
            }
        }
    }

    func captureFullScreen() {
        guard ensurePermission() else { return }
        let screen = Self.screenUnderMouse()
        Task { await performDisplayCapture(screen: screen, rect: nil) }
    }

    func timedCapture(seconds: Int) {
        guard ensurePermission(), countdown == nil else { return }
        countdown = CountdownHUD(seconds: seconds, on: Self.screenUnderMouse()) { [weak self] in
            self?.countdown = nil
            self?.captureFullScreen()
        }
    }

    // MARK: - Flow

    private func handleOverlay(_ result: SelectionOverlayController.Result) {
        overlay = nil
        switch result {
        case .cancelled:
            break
        case .region(let screen, let rect):
            Task { await performDisplayCapture(screen: screen, rect: rect) }
        case .window(let scWindow):
            Task {
                do {
                    let image = try await CaptureEngine.captureWindow(
                        scWindow,
                        showsCursor: AppSettings.shared.showCursor
                    )
                    let scale = scWindow.frame.width > 0
                        ? CGFloat(image.width) / scWindow.frame.width
                        : 2
                    presentCapture(Capture(image: image, scale: max(1, scale.rounded()), sourceScreen: Self.screenUnderMouse()))
                } catch {
                    showError(error)
                }
            }
        }
    }

    private func performDisplayCapture(screen: NSScreen, rect: CGRect?) async {
        do {
            // Give the overlay windows a beat to disappear from screen.
            try await Task.sleep(nanoseconds: 180_000_000)
            let image = try await CaptureEngine.captureDisplay(
                screen: screen,
                cropTo: rect,
                showsCursor: AppSettings.shared.showCursor
            )
            presentCapture(Capture(image: image, scale: screen.backingScaleFactor, sourceScreen: screen))
        } catch {
            showError(error)
        }
    }

    private func presentCapture(_ capture: Capture) {
        let panel = PostCapturePanel(capture: capture, stackIndex: panels.count)
        panel.onEdit = { [weak self, weak panel] in
            self?.openEditor(for: capture)
            if let panel { self?.removePanel(panel) }
        }
        panel.onDismiss = { [weak self, weak panel] in
            if let panel { self?.removePanel(panel) }
        }
        panels.append(panel)
        panel.show()
    }

    private func removePanel(_ panel: PostCapturePanel) {
        panel.close()
        panels.removeAll { $0 === panel }
    }

    private func openEditor(for capture: Capture) {
        let editor = EditorWindow(capture: capture) { [weak self] closed in
            self?.editors.removeAll { $0 === closed }
        }
        editors.append(editor)
    }

    // MARK: - Permission & misc

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = """
        Super Duper Screenshot needs Screen Recording access to capture your screen.

        Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch the app.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Capture Failed"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
