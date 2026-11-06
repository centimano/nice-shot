import AppKit
import SwiftUI

/// ZoomIt-style "draw on the screen" mode: freezes the display under the
/// mouse into a borderless fullscreen window and lets the user annotate it
/// with the editor's tools, then copy/save the result or hand it to the
/// full editor.

// MARK: - Commands (pure, unit-tested)

enum ScreenDrawCommand: Equatable {
    case exit
    case endTextEditing
    case undo
    case redo
    case copy
    case save
    case openEditor
    case deleteSelection
    case clear
    case selectTool(Tool)
    case board(BoardStyle)
}

/// ZoomIt-style board backgrounds: swap the frozen screenshot for a solid
/// white or black canvas. Pressing the same key again restores the screenshot.
enum BoardStyle: Hashable {
    case white
    case black
}

enum ScreenDrawKeys {
    /// Map a key-down to a mode command. While a text annotation is being
    /// edited only Esc is intercepted (ending the edit) so typing stays with
    /// the text field. Returns nil for keys the mode doesn't own.
    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        isEditingText: Bool
    ) -> ScreenDrawCommand? {
        if keyCode == 53 { return isEditingText ? .endTextEditing : .exit } // Esc
        if isEditingText { return nil }

        let mods = modifiers.intersection([.command, .shift, .option, .control])
        if mods.contains(.command) {
            guard !mods.contains(.option), !mods.contains(.control) else { return nil }
            switch characters?.lowercased() {
            case "z": return mods.contains(.shift) ? .redo : .undo
            case "c": return .copy
            case "s": return .save
            case "e": return .openEditor
            default: return nil
            }
        }
        guard mods.subtracting(.shift).isEmpty else { return nil }
        if keyCode == 51 { return .deleteSelection } // ⌫

        switch characters?.lowercased() {
        case "v": return .selectTool(.select)
        case "p": return .selectTool(.pen)
        case "h": return .selectTool(.highlighter)
        case "a": return .selectTool(.arrow)
        case "l": return .selectTool(.line)
        case "b": return .selectTool(.box)
        case "e": return .selectTool(.ellipse)
        case "t": return .selectTool(.text)
        case "w": return .board(.white)
        case "k": return .board(.black)
        default: return nil
        }
    }
}

// MARK: - Controller

@MainActor
final class ScreenDrawController {
    enum Result {
        case dismissed
        case openEditor(Capture, EditorDocument)
    }

    private let capture: Capture
    private let doc: EditorDocument
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var completion: ((Result) -> Void)?
    private var previousApp: NSRunningApplication?
    private var boardCache: [BoardStyle: CGImage] = [:]

    init(capture: Capture, initialTool: Tool = .pen) {
        self.capture = capture
        self.doc = EditorDocument(capture: capture)
        doc.tool = initialTool
    }

    /// `restoringFocusTo` lets the zoom-mode handoff pass along the app that
    /// was frontmost before zoom started (by handoff time we are frontmost).
    func begin(
        on screen: NSScreen,
        restoringFocusTo: NSRunningApplication? = nil,
        completion: @escaping (Result) -> Void
    ) {
        self.completion = completion
        previousApp = restoringFocusTo ?? NSWorkspace.shared.frontmostApplication

        // Fullscreen captures show 1:1; viewport crops from zoom mode are
        // smaller than the screen and scale up to fill it (staying magnified).
        let fitScale = capture.image.width > 0
            ? screen.frame.width / CGFloat(capture.image.width)
            : 1 / doc.unit
        let root = ScreenDrawView(doc: doc, fitScale: fitScale, notch: NotchGeometry(screen: screen)) { [weak self] command in
            self?.perform(command)
        }
        let w = ScreenOverlayWindow(contentRect: screen.frame)
        w.contentView = NSHostingView(rootView: root)
        window = w
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            guard let command = ScreenDrawKeys.command(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                characters: event.charactersIgnoringModifiers,
                isEditingText: self.doc.editingID != nil
            ) else { return event }
            self.perform(command)
            return nil
        }
    }

    private func perform(_ command: ScreenDrawCommand) {
        switch command {
        case .selectTool(let tool): doc.tool = tool
        case .board(let style): toggleBoard(style)
        case .endTextEditing: doc.endTextEditing()
        case .undo: doc.undo()
        case .redo: doc.redo()
        case .deleteSelection: doc.deleteSelected()
        case .clear: doc.clearAnnotations()
        case .exit: finish(.dismissed)
        case .copy: copyAndClose()
        case .save: saveAndClose()
        case .openEditor:
            doc.tool = .select
            finish(.openEditor(capture, doc))
        }
    }

    /// Swap in a solid white/black board, or back to the screenshot when the
    /// same board is already showing. Undoable like any other edit; identity
    /// comparison against the cached board image keeps the toggle correct
    /// even across undo/redo.
    private func toggleBoard(_ style: BoardStyle) {
        guard let board = boardImage(style) else { return }
        doc.replaceBaseImage(with: doc.baseImage === board ? capture.image : board)
    }

    private func boardImage(_ style: BoardStyle) -> CGImage? {
        if let cached = boardCache[style] { return cached }
        let size = doc.pixelSize
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let level: CGFloat = style == .white ? 1 : 0
        ctx.setFillColor(CGColor(red: level, green: level, blue: level, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let image = ctx.makeImage()
        boardCache[style] = image
        return image
    }

    private func copyAndClose() {
        guard let image = doc.renderFinal() else {
            finish(.dismissed)
            return
        }
        Exporter.copyToClipboard(image: image, scale: capture.scale)
        CaptureSound.play()
        finish(.dismissed)
    }

    /// The save panel runs below screenSaver window level, so hide the mode
    /// window first; a cancelled save brings it (and the drawings) back.
    private func saveAndClose() {
        guard let image = doc.renderFinal() else { return }
        window?.orderOut(nil)
        if Exporter.save(image: image, scale: capture.scale) {
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
        // close() (not just orderOut) frees the screen-sized backing store now.
        window?.orderOut(nil)
        window?.close()
        window = nil

        // Hand focus back on plain dismissal; the editor handoff activates
        // its own window instead.
        if case .dismissed = result,
           previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil

        completion(result)
    }
}

// MARK: - Camera notch (pure placement math is unit-tested)

/// The camera housing at the top of a notched MacBook display, in the
/// screen's view coordinates (origin top-left, points).
struct NotchGeometry: Equatable {
    var minX: CGFloat
    var maxX: CGFloat
    var height: CGFloat

    /// nil on screens without a notch (external displays, older Macs).
    /// The unobscured areas beside the notch give its horizontal extent;
    /// only their widths are used, so their coordinate origin doesn't matter.
    @MainActor
    init?(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        guard top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        self.init(screenWidth: screen.frame.width, leftAreaWidth: left.width, rightAreaWidth: right.width, height: top)
    }

    init?(screenWidth: CGFloat, leftAreaWidth: CGFloat, rightAreaWidth: CGFloat, height: CGFloat) {
        let minX = leftAreaWidth
        let maxX = screenWidth - rightAreaWidth
        guard height > 0, maxX > minX else { return nil }
        self.minX = minX
        self.maxX = maxX
        self.height = height
    }
}

/// Where the two halves of the draw strip go on a notched screen: flanking
/// the notch when each fits beside it, otherwise side by side just below it.
enum NotchPlacement {
    /// Distance of the strip from the top of the screen (unchanged from the
    /// single strip used on screens without a notch).
    static let topInset: CGFloat = 12
    /// Clearance between the strip and the notch, and between the halves.
    static let gap: CGFloat = 12
    /// Minimum distance from the screen's side edges.
    static let margin: CGFloat = 8

    static func frames(
        left: CGSize,
        right: CGSize,
        container: CGSize,
        notch: NotchGeometry
    ) -> (left: CGRect, right: CGRect, flanking: Bool) {
        let rowHeight = max(left.height, right.height)
        let fitsLeft = left.width <= notch.minX - gap - margin
        let fitsRight = right.width <= container.width - notch.maxX - gap - margin
        if fitsLeft && fitsRight {
            return (
                CGRect(
                    x: notch.minX - gap - left.width,
                    y: topInset + (rowHeight - left.height) / 2,
                    width: left.width, height: left.height
                ),
                CGRect(
                    x: notch.maxX + gap,
                    y: topInset + (rowHeight - right.height) / 2,
                    width: right.width, height: right.height
                ),
                true
            )
        }
        let top = max(topInset, notch.height + gap / 2)
        let total = left.width + gap + right.width
        let x = max(margin, (container.width - total) / 2)
        return (
            CGRect(x: x, y: top + (rowHeight - left.height) / 2, width: left.width, height: left.height),
            CGRect(
                x: x + left.width + gap,
                y: top + (rowHeight - right.height) / 2,
                width: right.width, height: right.height
            ),
            false
        )
    }
}

/// Lays out exactly two subviews (the strip halves) per `NotchPlacement`,
/// filling the whole screen so positions are in screen coordinates.
struct NotchAvoidingLayout: Layout {
    let notch: NotchGeometry

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            for subview in subviews {
                subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: .unspecified)
            }
            return
        }
        let leftSize = subviews[0].sizeThatFits(.unspecified)
        let rightSize = subviews[1].sizeThatFits(.unspecified)
        let frames = NotchPlacement.frames(left: leftSize, right: rightSize, container: bounds.size, notch: notch)
        subviews[0].place(
            at: CGPoint(x: bounds.minX + frames.left.minX, y: bounds.minY + frames.left.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(leftSize)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + frames.right.minX, y: bounds.minY + frames.right.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(rightSize)
        )
    }
}

// MARK: - Window (shared with zoom mode)

final class ScreenOverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - View

struct ScreenDrawView: View {
    @ObservedObject var doc: EditorDocument
    let fitScale: CGFloat
    /// The camera housing on a notched MacBook display, if this screen has one.
    var notch: NotchGeometry? = nil
    let perform: (ScreenDrawCommand) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            EditorCanvas(doc: doc, fitScale: fitScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let notch {
                // Keep the strip out from under the camera housing.
                NotchAvoidingLayout(notch: notch) {
                    ScreenDrawStrip(doc: doc, perform: perform, part: .toolsAndColors)
                    ScreenDrawStrip(doc: doc, perform: perform, part: .actions)
                }
            } else {
                ScreenDrawStrip(doc: doc, perform: perform)
                    .padding(.top, NotchPlacement.topInset)
            }
            VStack {
                Spacer()
                Text("⌘C copy · ⌘S save · ⌘E open in editor · esc close")
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
}

private struct ScreenDrawStrip: View {
    @ObservedObject var doc: EditorDocument
    let perform: (ScreenDrawCommand) -> Void

    private static let tools: [Tool] = [.select, .pen, .highlighter, .arrow, .line, .box, .ellipse, .text]

    static let palette: [(name: String, color: Color)] = [
        ("Red", Color(red: 0.93, green: 0.25, blue: 0.18)),
        ("Orange", Color(red: 0.98, green: 0.57, blue: 0.10)),
        ("Yellow", Color(red: 0.99, green: 0.83, blue: 0.10)),
        ("Green", Color(red: 0.17, green: 0.72, blue: 0.35)),
        ("Blue", Color(red: 0.10, green: 0.46, blue: 0.95)),
        ("Pink", Color(red: 0.95, green: 0.32, blue: 0.71)),
        ("White", .white),
        ("Black", .black),
    ]

    private let strokeWidths: [CGFloat] = [2, 4, 6, 10]

    /// Which part of the strip to show. On a screen with a camera notch the
    /// strip is shown as two halves, one on each side of the notch.
    enum Part {
        case whole
        case toolsAndColors
        case actions
    }

    var part: Part = .whole

    var body: some View {
        Group {
            switch part {
            case .whole:
                HStack(spacing: 10) {
                    toolsAndColors
                    actions
                }
            case .toolsAndColors:
                toolsAndColors
            case .actions:
                actions
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    /// Tool buttons and color swatches.
    private var toolsAndColors: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Self.tools) { tool in
                    Button {
                        perform(.selectTool(tool))
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(doc.tool == tool ? Color.accentColor.opacity(0.22) : .clear)
                    )
                    .foregroundStyle(doc.tool == tool ? Color.accentColor : Color.primary)
                    .help(tool.help)
                }
            }

            Divider().frame(height: 22)

            HStack(spacing: 5) {
                ForEach(Self.palette, id: \.name) { swatch in
                    Button {
                        doc.color = swatch.color
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 15, height: 15)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.35), lineWidth: 1))
                            .overlay {
                                if doc.color == swatch.color {
                                    Circle()
                                        .strokeBorder(Color.accentColor, lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                }
            }
        }
    }

    /// Boards, line weight, history, and the copy/save/editor/close actions.
    private var actions: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                boardButton(.white, help: "Whiteboard (W)")
                boardButton(.black, help: "Blackboard (K)")
            }

            Menu {
                ForEach(strokeWidths, id: \.self) { width in
                    Button {
                        doc.strokeWidth = width
                    } label: {
                        HStack {
                            Text("\(Int(width)) pt")
                            if doc.strokeWidth == width { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "lineweight")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)
            .help("Line Weight")

            Divider().frame(height: 22)

            iconButton("arrow.uturn.backward", "Undo (⌘Z)", disabled: !doc.canUndo) { perform(.undo) }
            iconButton("arrow.uturn.forward", "Redo (⇧⌘Z)", disabled: !doc.canRedo) { perform(.redo) }
            iconButton("trash", "Clear All Drawings", disabled: doc.annotations.isEmpty) { perform(.clear) }

            Divider().frame(height: 22)

            iconButton("doc.on.doc", "Copy and Close (⌘C)") { perform(.copy) }
            iconButton("square.and.arrow.down", "Save and Close (⌘S)") { perform(.save) }
            iconButton("pencil.and.outline", "Open in Editor (⌘E)") { perform(.openEditor) }
            iconButton("xmark.circle", "Close Without Saving (esc)") { perform(.exit) }
        }
    }

    private func boardButton(_ style: BoardStyle, help: String) -> some View {
        Button {
            perform(.board(style))
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(style == .white ? Color.white : Color.black)
                .frame(width: 18, height: 13)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconButton(
        _ symbol: String,
        _ help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
    }
}
