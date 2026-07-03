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
    private var screenDraw: ScreenDrawController?
    private var screenZoom: ScreenZoomController?

    /// Frozen per-display images taken when region selection starts. They feed
    /// the magnifier loupe and become the capture itself (cropped), so the
    /// result matches exactly what the user saw under the overlay.
    private var regionSnapshots: [CGDirectDisplayID: CGImage] = [:]

    // MARK: - Entry points

    func captureRegion() {
        guard ensurePermission(), overlay == nil else { return }
        Task {
            var snapshots: [CGDirectDisplayID: CGImage] = [:]
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if let image = try? await CaptureEngine.captureDisplay(
                    screen: screen,
                    cropTo: nil,
                    showsCursor: AppSettings.shared.showCursor
                ) {
                    snapshots[id] = image
                }
            }
            guard self.overlay == nil else { return }
            self.regionSnapshots = snapshots
            let controller = SelectionOverlayController(mode: .region, snapshots: snapshots)
            self.overlay = controller
            controller.begin { [weak self] result in self?.handleOverlay(result) }
        }
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

    /// ZoomIt-style screen draw: freeze the display under the mouse and
    /// annotate directly on it. The cursor is never baked into the frozen
    /// image — it would sit wherever the hotkey was pressed, under drawings.
    func drawOnScreen() {
        // The draw hotkey while zoom mode is active freezes the current
        // zoomed view and starts annotating it (ZoomIt behavior).
        if let screenZoom {
            screenZoom.enterDraw()
            return
        }
        guard ensurePermission(), screenDraw == nil, overlay == nil else { return }
        let screen = Self.screenUnderMouse()
        Task {
            do {
                let image = try await CaptureEngine.captureDisplay(
                    screen: screen,
                    cropTo: nil,
                    showsCursor: false
                )
                guard self.screenDraw == nil else { return }
                let capture = Capture(image: image, scale: screen.backingScaleFactor, sourceScreen: screen)
                self.presentScreenDraw(capture, on: screen)
            } catch {
                self.showError(error)
            }
        }
    }

    /// ZoomIt-style frozen zoom: freeze the display under the mouse, scroll
    /// to zoom toward the cursor, move to pan; tool keys hand the viewport
    /// off to screen draw mode.
    func zoomScreen() {
        guard ensurePermission(), screenZoom == nil, screenDraw == nil, overlay == nil else { return }
        let screen = Self.screenUnderMouse()
        Task {
            do {
                let image = try await CaptureEngine.captureDisplay(
                    screen: screen,
                    cropTo: nil,
                    showsCursor: false
                )
                guard self.screenZoom == nil, self.screenDraw == nil else { return }
                let capture = Capture(image: image, scale: screen.backingScaleFactor, sourceScreen: screen)
                let controller = ScreenZoomController(capture: capture)
                self.screenZoom = controller
                controller.begin(on: screen) { [weak self] result in
                    self?.screenZoom = nil
                    switch result {
                    case .dismissed:
                        break
                    case .enterDraw(let viewport, let tool, let previousApp):
                        self?.presentScreenDraw(viewport, on: screen, tool: tool, restoringFocusTo: previousApp)
                    case .openEditor(let viewport):
                        self?.openEditor(for: viewport)
                    }
                }
            } catch {
                self.showError(error)
            }
        }
    }

    private func presentScreenDraw(
        _ capture: Capture,
        on screen: NSScreen,
        tool: Tool = .pen,
        restoringFocusTo: NSRunningApplication? = nil
    ) {
        let controller = ScreenDrawController(capture: capture, initialTool: tool)
        screenDraw = controller
        controller.begin(on: screen, restoringFocusTo: restoringFocusTo) { [weak self] result in
            self?.screenDraw = nil
            if case .openEditor(let capture, let document) = result {
                self?.openEditor(for: capture, document: document)
            }
        }
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
        defer { regionSnapshots = [:] }
        switch result {
        case .cancelled:
            break
        case .region(let screen, let rect):
            let scale = screen.backingScaleFactor
            if let id = screen.displayID,
               let snapshot = regionSnapshots[id],
               let cropped = snapshot.cropping(to: CaptureEngine.pixelRect(for: rect, scale: scale)) {
                // Instant: crop the frozen snapshot the user was just looking at.
                presentCapture(Capture(image: cropped, scale: scale, sourceScreen: screen))
            } else {
                Task { await performDisplayCapture(screen: screen, rect: rect) }
            }
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
        CaptureSound.play()
        let autoCopied = AppSettings.shared.autoCopy
        if autoCopied {
            Exporter.copyToClipboard(image: capture.image, scale: capture.scale)
        }
        switch AppSettings.shared.postCaptureAction {
        case .panel:
            showPanel(for: capture, autoCopied: autoCopied)
        case .copy:
            if !autoCopied {
                Exporter.copyToClipboard(image: capture.image, scale: capture.scale)
            }
        case .save:
            Exporter.save(image: capture.image, scale: capture.scale)
        case .edit:
            openEditor(for: capture)
        }
    }

    private func showPanel(for capture: Capture, autoCopied: Bool) {
        let panel = PostCapturePanel(capture: capture, stackIndex: panels.count, autoCopied: autoCopied)
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

    private func openEditor(for capture: Capture, document: EditorDocument? = nil) {
        let editor = EditorWindow(capture: capture, document: document) { [weak self] closed in
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
        Nice Shot needs Screen Recording access to capture your screen.

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
