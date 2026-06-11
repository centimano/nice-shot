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
    private let snapshots: [CGDirectDisplayID: CGImage]
    private var overlays: [OverlayWindow] = []
    private var keyMonitor: Any?
    private var completion: ((Result) -> Void)?
    private var previousApp: NSRunningApplication?

    init(mode: Mode, windows: [SCWindow] = [], snapshots: [CGDirectDisplayID: CGImage] = [:]) {
        self.mode = mode
        self.scWindows = windows
        self.snapshots = snapshots
    }

    func begin(completion: @escaping (Result) -> Void) {
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication

        for screen in NSScreen.screens {
            let snapshot = screen.displayID.flatMap { snapshots[$0] }
            let overlay = OverlayWindow(screen: screen, mode: mode, scWindows: scWindows, snapshot: snapshot) { [weak self] result in
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

// MARK: - Coordinate conversion

/// SCWindow frames arrive in global CoreGraphics coordinates (origin at the
/// top-left of the primary display, y growing downward). Overlay views are
/// flipped and local to one screen, so picker rects must be converted.
enum ScreenGeometry {
    static func localRect(globalCG frame: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        let originX = screenFrame.minX
        let originY = primaryHeight - screenFrame.maxY
        return CGRect(
            x: frame.minX - originX,
            y: frame.minY - originY,
            width: frame.width,
            height: frame.height
        )
    }
}

// MARK: - Magnifier loupe geometry (pure math, unit-tested)

enum LoupeGeometry {
    static let diameter: CGFloat = 110 // points on screen
    static let zoom: CGFloat = 6 // magnification factor

    /// Square region of the snapshot (in image pixels) the loupe magnifies,
    /// clamped so it never reads outside the image.
    static func sourceRect(around cursor: CGPoint, imageScale: CGFloat, imageSize: CGSize) -> CGRect {
        let side = diameter / zoom * imageScale
        var rect = CGRect(
            x: cursor.x * imageScale - side / 2,
            y: cursor.y * imageScale - side / 2,
            width: side,
            height: side
        )
        rect.origin.x = rect.origin.x.clamped(0, max(0, imageSize.width - side))
        rect.origin.y = rect.origin.y.clamped(0, max(0, imageSize.height - side))
        return rect
    }

    /// Loupe placement: offset from the cursor, flipping to the other side
    /// near screen edges so it stays fully visible.
    static func origin(cursor: CGPoint, in bounds: CGRect) -> CGPoint {
        let gap: CGFloat = 24
        let margin: CGFloat = 8
        var x = cursor.x + gap
        var y = cursor.y + gap
        if x + diameter > bounds.maxX - margin { x = cursor.x - gap - diameter }
        if y + diameter > bounds.maxY - margin { y = cursor.y - gap - diameter }
        return CGPoint(x: max(bounds.minX + margin, x), y: max(bounds.minY + margin, y))
    }
}

// MARK: - Window

private final class OverlayWindow: NSWindow {
    init(
        screen: NSScreen,
        mode: SelectionOverlayController.Mode,
        scWindows: [SCWindow],
        snapshot: CGImage?,
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
        contentView = OverlayView(screen: screen, mode: mode, scWindows: scWindows, snapshot: snapshot, onResult: onResult)
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - View

private final class OverlayView: NSView {
    private let screen: NSScreen
    private let mode: SelectionOverlayController.Mode
    private let onResult: (SelectionOverlayController.Result) -> Void

    /// Frozen image of this screen, used by the magnifier loupe.
    private let snapshot: CGImage?
    private let snapshotScale: CGFloat

    /// Windows under the picker, front-to-back, with frames converted to this
    /// view's flipped local coordinates.
    private var pickableWindows: [(window: SCWindow, localFrame: CGRect)] = []

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var lastMouse: CGPoint?
    private var hovered: (window: SCWindow, localFrame: CGRect)?

    override var isFlipped: Bool { true }

    init(
        screen: NSScreen,
        mode: SelectionOverlayController.Mode,
        scWindows: [SCWindow],
        snapshot: CGImage?,
        onResult: @escaping (SelectionOverlayController.Result) -> Void
    ) {
        self.screen = screen
        self.mode = mode
        self.snapshot = snapshot
        self.snapshotScale = screen.backingScaleFactor
        self.onResult = onResult
        super.init(frame: .zero)

        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        pickableWindows = scWindows.map { w in
            (w, ScreenGeometry.localRect(globalCG: w.frame, screenFrame: screen.frame, primaryHeight: primaryHeight))
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            lastMouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        lastMouse = p
        if mode == .window {
            let hit = pickableWindows.first { $0.localFrame.contains(p) }
            if hit?.window.windowID != hovered?.window.windowID {
                hovered = hit
            }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard mode == .region else { return }
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        lastMouse = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        lastMouse = dragCurrent
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

        if mode == .region, let cursor = lastMouse, bounds.contains(cursor) {
            drawLoupe(at: cursor)
        }
    }

    /// Magnified, pixel-crisp view of the frozen snapshot around the cursor,
    /// with a crosshair and the cursor's pixel coordinates.
    private func drawLoupe(at cursor: CGPoint) {
        guard let snapshot else { return }
        let imageSize = CGSize(width: snapshot.width, height: snapshot.height)
        let source = LoupeGeometry.sourceRect(around: cursor, imageScale: snapshotScale, imageSize: imageSize)
        guard source.width > 0, let cropped = snapshot.cropping(to: source) else { return }

        let rect = CGRect(
            origin: LoupeGeometry.origin(cursor: cursor, in: bounds),
            size: CGSize(width: LoupeGeometry.diameter, height: LoupeGeometry.diameter)
        )
        let circle = NSBezierPath(ovalIn: rect)

        NSGraphicsContext.current?.saveGraphicsState()
        circle.addClip()
        NSImage(cgImage: cropped, size: rect.size).draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none.rawValue as NSNumber]
        )

        // Crosshair through the magnified cursor pixel (off-center only when
        // the source rect was clamped at a screen edge).
        let cx = rect.minX + (cursor.x * snapshotScale - source.minX) / source.width * rect.width
        let cy = rect.minY + (cursor.y * snapshotScale - source.minY) / source.height * rect.height
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: cx, y: rect.minY))
        cross.line(to: CGPoint(x: cx, y: rect.maxY))
        cross.move(to: CGPoint(x: rect.minX, y: cy))
        cross.line(to: CGPoint(x: rect.maxX, y: cy))
        cross.lineWidth = 1
        cross.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.white.setStroke()
        circle.lineWidth = 2
        circle.stroke()

        drawBadge(
            "\(Int(cursor.x * snapshotScale)), \(Int(cursor.y * snapshotScale)) px",
            at: CGPoint(x: rect.midX, y: min(rect.maxY + 18, bounds.maxY - 14))
        )
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
