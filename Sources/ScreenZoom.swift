import AppKit
import SwiftUI

/// ZoomIt-style frozen zoom: freezes the display under the mouse into a
/// borderless fullscreen window, scroll zooms toward the cursor, moving the
/// mouse pans, and any tool key hands the visible viewport off to screen
/// draw mode for annotation.

// MARK: - Geometry (pure, unit-tested)

/// All zoom geometry is derived from two values: the magnification and the
/// cursor position as a 0–1 fraction of the view (x right, y down, matching
/// image-pixel coordinates). The viewport origin maps that fraction across
/// the pan range — `origin = f × (imageSize − viewportSize)` — which has a
/// pleasant consequence: the image point under the cursor is always
/// `f × imageSize`, independent of magnification. Zooming therefore keeps
/// the point under the cursor fixed, and moving the mouse pans edge-to-edge.
enum ZoomMath {
    static let magnificationRange: ClosedRange<CGFloat> = 1...8

    static func clamped(_ magnification: CGFloat) -> CGFloat {
        min(max(magnification, magnificationRange.lowerBound), magnificationRange.upperBound)
    }

    /// Exponential zoom: one step doubles (or halves) the magnification.
    static func magnification(after steps: CGFloat, from current: CGFloat) -> CGFloat {
        clamped(current * pow(2, steps))
    }

    /// The part of the image visible in the viewport, in image pixels.
    static func visibleRect(imageSize: CGSize, magnification: CGFloat, focus: CGPoint) -> CGRect {
        let m = clamped(magnification)
        let size = CGSize(width: imageSize.width / m, height: imageSize.height / m)
        let fx = min(max(focus.x, 0), 1)
        let fy = min(max(focus.y, 0), 1)
        return CGRect(
            x: fx * (imageSize.width - size.width),
            y: fy * (imageSize.height - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// Integral pixel rect for cropping the capture to the viewport.
    static func cropRect(imageSize: CGSize, magnification: CGFloat, focus: CGPoint) -> CGRect {
        visibleRect(imageSize: imageSize, magnification: magnification, focus: focus)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }
}

// MARK: - Commands (pure, unit-tested)

enum ScreenZoomCommand: Equatable {
    case exit
    case zoomIn
    case zoomOut
    case copy
    case save
    case openEditor
    case enterDraw(Tool)
}

enum ScreenZoomKeys {
    /// Map a key-down to a mode command. Returns nil for keys the mode
    /// doesn't own. Zoom mode has no text editing, so unlike screen draw
    /// there is no pass-through state.
    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?
    ) -> ScreenZoomCommand? {
        if keyCode == 53 { return .exit } // Esc

        let mods = modifiers.intersection([.command, .shift, .option, .control])
        if mods.contains(.command) {
            guard !mods.contains(.option), !mods.contains(.control) else { return nil }
            switch characters?.lowercased() {
            case "c": return .copy
            case "s": return .save
            case "e": return .openEditor
            default: return nil
            }
        }
        guard mods.subtracting(.shift).isEmpty else { return nil }
        if keyCode == 126 { return .zoomIn } // ↑
        if keyCode == 125 { return .zoomOut } // ↓

        switch characters?.lowercased() {
        case "v": return .enterDraw(.select)
        case "p", "d": return .enterDraw(.pen)
        case "h": return .enterDraw(.highlighter)
        case "a": return .enterDraw(.arrow)
        case "l": return .enterDraw(.line)
        case "b": return .enterDraw(.box)
        case "e": return .enterDraw(.ellipse)
        case "t": return .enterDraw(.text)
        default: return nil
        }
    }
}

// MARK: - Controller

@MainActor
final class ScreenZoomController {
    enum Result {
        case dismissed
        /// Hand the current viewport to screen draw mode. Carries the app
        /// that was frontmost before zoom started so draw mode can restore
        /// focus to it on plain dismissal.
        case enterDraw(Capture, Tool, NSRunningApplication?)
        case openEditor(Capture)
    }

    private let capture: Capture
    private let model = ZoomHUDModel()
    private var surface: ZoomContentView?
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var completion: ((Result) -> Void)?
    private var previousApp: NSRunningApplication?

    init(capture: Capture) {
        self.capture = capture
    }

    func begin(on screen: NSScreen, completion: @escaping (Result) -> Void) {
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication

        let surface = ZoomContentView(image: capture.image, model: model)
        surface.onDoubleClick = { [weak self] in self?.perform(.exit) }
        self.surface = surface

        let w = ScreenOverlayWindow(contentRect: screen.frame)
        w.contentView = NSHostingView(rootView: ScreenZoomView(model: model, surface: surface))
        window = w
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            guard let command = ScreenZoomKeys.command(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                characters: event.charactersIgnoringModifiers
            ) else { return event }
            self.perform(command)
            return nil
        }
    }

    /// Entry point for the global draw hotkey (⌃⇧D) while zoom is active.
    func enterDraw(with tool: Tool = .pen) {
        perform(.enterDraw(tool))
    }

    private func perform(_ command: ScreenZoomCommand) {
        switch command {
        case .exit: finish(.dismissed)
        case .zoomIn: surface?.step(1)
        case .zoomOut: surface?.step(-1)
        case .copy: copyAndClose()
        case .save: saveAndClose()
        case .openEditor:
            guard let viewport = viewportCapture() else { return }
            finish(.openEditor(viewport))
        case .enterDraw(let tool):
            guard let viewport = viewportCapture() else { return }
            finish(.enterDraw(viewport, tool, previousApp))
        }
    }

    /// The capture cropped to what's on screen right now.
    private func viewportCapture() -> Capture? {
        guard let surface else { return nil }
        if surface.magnification <= 1 { return capture }
        let imageSize = CGSize(width: capture.image.width, height: capture.image.height)
        let rect = ZoomMath.cropRect(
            imageSize: imageSize,
            magnification: surface.magnification,
            focus: surface.focus
        )
        guard let cropped = capture.image.cropping(to: rect) else { return nil }
        return Capture(image: cropped, scale: capture.scale, sourceScreen: capture.sourceScreen)
    }

    private func copyAndClose() {
        guard let viewport = viewportCapture() else {
            finish(.dismissed)
            return
        }
        Exporter.copyToClipboard(image: viewport.image, scale: viewport.scale)
        CaptureSound.play()
        finish(.dismissed)
    }

    /// Same dance as screen draw: the save panel runs below screenSaver
    /// window level, so hide the mode window first; cancel brings it back.
    private func saveAndClose() {
        guard let viewport = viewportCapture() else { return }
        window?.orderOut(nil)
        if Exporter.save(image: viewport.image, scale: viewport.scale) {
            CaptureSound.play()
            finish(.dismissed)
        } else {
            window?.orderFrontRegardless()
            window?.makeKey()
        }
    }

    private func finish(_ result: Result) {
        guard let completion else { return }
        self.completion = nil

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        // The draw handoff creates its window inside the completion; run it
        // before hiding ours so the desktop never flashes through.
        completion(result)

        window?.orderOut(nil)
        window = nil
        surface = nil

        if case .dismissed = result,
           previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
}

// MARK: - Zoom surface (AppKit: scroll wheel + mouse-move tracking)

@MainActor
final class ZoomHUDModel: ObservableObject {
    @Published var magnification: CGFloat = 1
}

final class ZoomContentView: NSView {
    private let image: CGImage
    private let model: ZoomHUDModel

    private(set) var magnification: CGFloat = 1
    /// Cursor position as a 0–1 fraction of the view (x right, y down).
    private(set) var focus = CGPoint(x: 0.5, y: 0.5)
    var onDoubleClick: (() -> Void)?

    init(image: CGImage, model: ZoomHUDModel) {
        self.image = image
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func step(_ steps: CGFloat) {
        setMagnification(ZoomMath.magnification(after: steps, from: magnification))
    }

    private func setMagnification(_ value: CGFloat) {
        guard value != magnification else { return }
        magnification = value
        model.magnification = value
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        updateFocus(from: event)
        if magnification > 1 { needsDisplay = true }
    }

    override func scrollWheel(with event: NSEvent) {
        updateFocus(from: event)
        // Precise (trackpad) deltas arrive in points, wheel deltas in lines.
        let steps = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / 120
            : event.scrollingDeltaY / 4
        setMagnification(ZoomMath.magnification(after: steps, from: magnification))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
    }

    private func updateFocus(from event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        focus = CGPoint(
            x: min(max(p.x / bounds.width, 0), 1),
            y: min(max(1 - p.y / bounds.height, 0), 1)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let imageSize = CGSize(width: image.width, height: image.height)
        let visible = ZoomMath.visibleRect(
            imageSize: imageSize,
            magnification: magnification,
            focus: focus
        )
        // Map the visible rect (top-left image coordinates) onto the whole
        // view (bottom-left AppKit coordinates).
        let scale = bounds.width / visible.width
        let dest = CGRect(
            x: -visible.minX * scale,
            y: -(imageSize.height - visible.maxY) * scale,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        ctx.interpolationQuality = .high
        ctx.draw(image, in: dest)
    }
}

// MARK: - SwiftUI shell (hint bar over the AppKit surface)

private struct ZoomSurface: NSViewRepresentable {
    let view: ZoomContentView
    func makeNSView(context: Context) -> ZoomContentView { view }
    func updateNSView(_ nsView: ZoomContentView, context: Context) {}
}

private struct ScreenZoomView: View {
    @ObservedObject var model: ZoomHUDModel
    let surface: ZoomContentView

    var body: some View {
        ZStack {
            ZoomSurface(view: surface)
                .ignoresSafeArea()
            VStack {
                Spacer()
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 10)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var hint: String {
        let zoom = model.magnification <= 1
            ? "scroll to zoom"
            : String(format: "%.1f×", model.magnification)
        return "\(zoom) · move to pan · P/A/B… to draw · ⌘C copy · ⌘S save · ⌘E editor · esc close"
    }
}
