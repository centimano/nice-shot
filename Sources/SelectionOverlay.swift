import AppKit
import ScreenCaptureKit

/// Full-screen dimming overlays (one per display) used for region drag-select
/// and click-to-capture window picking.
@MainActor
final class SelectionOverlayController {
    enum Mode {
        case region
        case window
    }

    enum Result {
        case cancelled
        case region(NSScreen, CGRect) // rect in screen points, top-left origin relative to that screen
        case window(SCWindow)
    }

    private let mode: Mode
    private let scWindows: [SCWindow]
    private var overlays: [OverlayWindow] = []
    private var keyMonitor: Any?
    private var completion: ((Result) -> Void)?
    private var previousApp: NSRunningApplication?

    init(mode: Mode, windows: [SCWindow] = []) {
        self.mode = mode
        self.scWindows = windows
    }

    func begin(completion: @escaping (Result) -> Void) {
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen, mode: mode, scWindows: scWindows) { [weak self] result in
                self?.finish(result)
            }
            overlays.append(overlay)
            overlay.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        overlays.first?.makeKey()
        NSCursor.crosshair.push()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.finish(.cancelled)
                return nil
            }
            return event
        }
    }

    private func finish(_ result: Result) {
        guard let completion else { return }
        self.completion = nil

        NSCursor.pop()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()

        // Hand focus back to whatever the user was working in, so the capture
        // looks exactly like their screen did and they can keep typing.
        if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil

        completion(result)
    }
}

// MARK: - Window

private final class OverlayWindow: NSWindow {
    init(
        screen: NSScreen,
        mode: SelectionOverlayController.Mode,
        scWindows: [SCWindow],
        onResult: @escaping (SelectionOverlayController.Result) -> Void
    ) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = OverlayView(screen: screen, mode: mode, scWindows: scWindows, onResult: onResult)
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - View

private final class OverlayView: NSView {
    private let screen: NSScreen
    private let mode: SelectionOverlayController.Mode
    private let onResult: (SelectionOverlayController.Result) -> Void

    /// Windows under the picker, front-to-back, with frames converted to this
    /// view's flipped local coordinates.
    private var pickableWindows: [(window: SCWindow, localFrame: CGRect)] = []

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var hovered: (window: SCWindow, localFrame: CGRect)?

    override var isFlipped: Bool { true }

    init(
        screen: NSScreen,
        mode: SelectionOverlayController.Mode,
        scWindows: [SCWindow],
        onResult: @escaping (SelectionOverlayController.Result) -> Void
    ) {
        self.screen = screen
        self.mode = mode
        self.onResult = onResult
        super.init(frame: .zero)

        // SCWindow frames are in global CG coordinates (top-left origin at the
        // primary display's top-left). Convert to this screen's local top-left
        // coordinates, which match this flipped view.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let screenCGOrigin = CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
        pickableWindows = scWindows.map { w in
            let local = CGRect(
                x: w.frame.minX - screenCGOrigin.x,
                y: w.frame.minY - screenCGOrigin.y,
                width: w.frame.width,
                height: w.frame.height
            )
            return (w, local)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited],
            owner: self
        ))
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let p = convert(event.locationInWindow, from: nil)
        let hit = pickableWindows.first { $0.localFrame.contains(p) }
        if hit?.window.windowID != hovered?.window.windowID {
            hovered = hit
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard mode == .region else { return }
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .region:
            guard let start = dragStart else { return }
            let end = convert(event.locationInWindow, from: nil)
            let rect = CGRect(points: start, end)
            dragStart = nil
            dragCurrent = nil
            if rect.width > 3, rect.height > 3 {
                onResult(.region(screen, rect))
            } else {
                onResult(.cancelled)
            }
        case .window:
            let p = convert(event.locationInWindow, from: nil)
            if let hit = pickableWindows.first(where: { $0.localFrame.contains(p) }) {
                onResult(.window(hit.window))
            } else {
                onResult(.cancelled)
            }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        let activeRect: CGRect?
        switch mode {
        case .region:
            if let s = dragStart, let c = dragCurrent {
                activeRect = CGRect(points: s, c)
            } else {
                activeRect = nil
            }
        case .window:
            activeRect = hovered?.localFrame
        }

        if let rect = activeRect {
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: -0.75, dy: -0.75))
            path.lineWidth = 1.5
            path.stroke()

            let label: String
            switch mode {
            case .region:
                label = "\(Int(rect.width)) × \(Int(rect.height))"
            case .window:
                label = hovered?.window.owningApplication?.applicationName
                    ?? hovered?.window.title ?? "Window"
            }
            drawBadge(label, at: CGPoint(x: rect.midX, y: min(rect.maxY + 22, bounds.maxY - 16)))
        } else {
            let hint = mode == .region
                ? "Drag to select a region — Esc to cancel"
                : "Click a window to capture it — Esc to cancel"
            drawBadge(hint, at: CGPoint(x: bounds.midX, y: bounds.minY + 60))
        }
    }

    private func drawBadge(_ text: String, at center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 8
        let rect = CGRect(
            x: center.x - size.width / 2 - pad,
            y: center.y - size.height / 2 - pad / 2,
            width: size.width + pad * 2,
            height: size.height + pad
        )
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        str.draw(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad / 2))
    }
}
