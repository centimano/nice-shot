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
        let root = ScreenDrawView(doc: doc, fitScale: fitScale) { [weak self] command in
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
        window?.orderOut(nil)
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
    let perform: (ScreenDrawCommand) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            EditorCanvas(doc: doc, fitScale: fitScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ScreenDrawStrip(doc: doc, perform: perform)
                .padding(.top, 12)
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

    var body: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
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
