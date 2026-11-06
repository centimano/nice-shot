import AppKit
import SwiftUI

/// The capture tray: when captures pile up faster than they're dealt with,
/// one floating panel holds them all instead of a stack of separate panels.
/// A single capture still gets the classic `PostCapturePanel`; the second
/// capture taken while that panel is showing folds both into a tray, which
/// stays until every capture in it has been handled.

// MARK: - Routing (pure, unit-tested)

enum CaptureRouting {
    enum Destination: Equatable {
        /// Nothing showing: the classic single-capture panel.
        case panel
        /// A panel is showing: replace it with a tray holding both captures.
        case startTray
        /// A tray is already showing: add to it.
        case tray
    }

    static func destination(panelShowing: Bool, trayShowing: Bool) -> Destination {
        if trayShowing { return .tray }
        return panelShowing ? .startTray : .panel
    }
}

// MARK: - Model (pure, unit-tested)

struct CaptureTrayItem: Identifiable {
    let id: UUID
    let capture: Capture
    let thumbnail: NSImage
    /// True while this capture is what Nice Shot last put on the clipboard.
    var onClipboard: Bool

    var sizeLabel: String { "\(capture.image.width) × \(capture.image.height) px" }
}

/// The tray's contents, newest first.
struct CaptureTrayItems {
    private(set) var items: [CaptureTrayItem] = []

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// Captures in the order they were taken (for Save All numbering).
    var oldestFirst: [CaptureTrayItem] { items.reversed() }

    func item(_ id: UUID) -> CaptureTrayItem? {
        items.first { $0.id == id }
    }

    /// Add a capture on top. An auto-copied capture replaced whatever was
    /// on the clipboard, so older items lose their "copied" mark.
    mutating func add(_ item: CaptureTrayItem) {
        if item.onClipboard { clipboardChanged() }
        items.insert(item, at: 0)
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> CaptureTrayItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// Something else was copied; no item is on the clipboard any more.
    mutating func clipboardChanged() {
        for index in items.indices { items[index].onClipboard = false }
    }
}

// MARK: - Layout (pure, unit-tested)

/// Fixed metrics, so the window size is computed exactly rather than measured
/// from SwiftUI — the panel stays pinned to the screen corner as it grows.
enum CaptureTrayLayout {
    static let cardWidth: CGFloat = 330
    static let shadowPadding: CGFloat = 20
    static let cardPadding: CGFloat = 12
    static let headerHeight: CGFloat = 28
    static let sectionSpacing: CGFloat = 8
    static let rowHeight: CGFloat = 64
    static let rowSpacing: CGFloat = 6
    static let collapsedHeight: CGFloat = 56
    static let thumbnailSize = CGSize(width: 96, height: 60)
    /// Rows shown before the list scrolls.
    static let maxVisibleRows = 4

    static func needsScrolling(count: Int) -> Bool { count > maxVisibleRows }

    /// Height of the scrolling list. Past `maxVisibleRows` half of the next
    /// row peeks out, hinting that there's more to scroll to.
    static func listHeight(count: Int) -> CGFloat {
        let shown = min(max(count, 1), maxVisibleRows)
        var height = CGFloat(shown) * rowHeight + CGFloat(shown - 1) * rowSpacing
        if needsScrolling(count: count) { height += rowSpacing + rowHeight / 2 }
        return height
    }

    static func cardHeight(count: Int, expanded: Bool) -> CGFloat {
        let content = expanded
            ? headerHeight + sectionSpacing + listHeight(count: count)
            : collapsedHeight
        return content + cardPadding * 2
    }

    /// Window size including the transparent margin the card's shadow uses.
    static func windowSize(count: Int, expanded: Bool) -> CGSize {
        CGSize(
            width: cardWidth + shadowPadding * 2,
            height: cardHeight(count: count, expanded: expanded) + shadowPadding * 2
        )
    }
}

// MARK: - Controller

@MainActor
final class CaptureTray {
    /// Open this capture in the editor (the tray has already dropped it).
    var onEdit: ((Capture) -> Void)?
    /// The last capture was handled; the tray has closed itself.
    var onEmpty: (() -> Void)?

    private static let expandedKey = "captureTrayExpanded"

    private var model = CaptureTrayItems()
    private var expanded: Bool {
        didSet { UserDefaults.standard.set(expanded, forKey: Self.expandedKey) }
    }
    private let panel: NSPanel
    private let hosting: NSHostingView<CaptureTrayView>
    private let displayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var isOpen = false

    var isEmpty: Bool { model.isEmpty }
    var count: Int { model.count }

    /// `screen` is where the tray lives (the first capture's screen).
    init(screen: NSScreen?) {
        displayID = screen?.displayID
        expanded = UserDefaults.standard.object(forKey: Self.expandedKey) as? Bool ?? true

        let hosting = NSHostingView(rootView: CaptureTrayView.empty)
        // The controller sizes the window itself (see CaptureTrayLayout);
        // keep the hosting view from also driving the window size.
        hosting.sizingOptions = []
        self.hosting = hosting

        let size = CaptureTrayLayout.windowSize(count: 1, expanded: expanded)
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
    }

    /// Add a capture on top. `id` lets a capture keep its identity when it
    /// moves over from the classic panel.
    func add(_ capture: Capture, autoCopied: Bool, id: UUID = UUID()) {
        model.add(CaptureTrayItem(
            id: id,
            capture: capture,
            thumbnail: Thumbnail.make(from: capture.image, maxPoints: CaptureTrayLayout.thumbnailSize),
            onClipboard: autoCopied
        ))
        refresh()
    }

    /// Drop a capture that was dealt with elsewhere.
    func remove(id: UUID) {
        guard model.remove(id) != nil else { return }
        refresh()
    }

    func show() {
        guard !isOpen else { return }
        isOpen = true
        refresh()
        panel.orderFrontRegardless()
        CaptureExclusions.add(panel)
        // The Dock or display arrangement changing moves the usable area.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func close() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        guard isOpen else { return }
        isOpen = false
        CaptureExclusions.remove(panel)
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Rendering

    private func refresh() {
        if model.isEmpty {
            close()
            onEmpty?()
            return
        }
        hosting.rootView = CaptureTrayView(
            items: model.items,
            expanded: expanded,
            saveLabel: AppSettings.shared.askWhereToSave ? "Save…" : "Save",
            saveAllLabel: AppSettings.shared.askWhereToSave ? "Save All…" : "Save All",
            actions: CaptureTrayActions(
                edit: { [weak self] id in self?.edit(id) },
                save: { [weak self] id in self?.save(id) },
                copy: { [weak self] id in self?.copy(id) },
                discard: { [weak self] id in self?.remove(id: id) },
                saveAll: { [weak self] in self?.saveAll() },
                discardAll: { [weak self] in self?.discardAll() },
                toggleExpanded: { [weak self] in self?.toggleExpanded() }
            )
        )
        let size = CaptureTrayLayout.windowSize(count: model.count, expanded: expanded)
        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
        let origin = screen.map {
            FloatingPanelPlacement.origin(windowSize: size, visibleFrame: $0.visibleFrame)
        } ?? panel.frame.origin
        panel.setFrame(CGRect(origin: origin, size: size), display: isOpen)
    }

    // MARK: Actions

    private func toggleExpanded() {
        expanded.toggle()
        refresh()
    }

    private func edit(_ id: UUID) {
        guard let item = model.remove(id) else { return }
        onEdit?(item.capture)
        refresh()
    }

    private func save(_ id: UUID) {
        guard let item = model.item(id) else { return }
        // A cancelled dialog keeps the capture in the tray.
        if Exporter.save(image: item.capture.image, scale: item.capture.scale) {
            remove(id: id)
        }
    }

    private func copy(_ id: UUID) {
        guard let item = model.remove(id) else { return }
        Exporter.copyToClipboard(image: item.capture.image, scale: item.capture.scale)
        model.clipboardChanged()
        refresh()
    }

    /// Save every capture shown when the button was pressed (captures taken
    /// while a folder picker is open stay put). Saved ones leave the tray.
    private func saveAll() {
        let batch = model.oldestFirst
        let results = Exporter.saveBatch(batch.map { (image: $0.capture.image, scale: $0.capture.scale) })
        var changed = false
        for (item, saved) in zip(batch, results) where saved {
            changed = model.remove(item.id) != nil || changed
        }
        if changed { refresh() }
    }

    private func discardAll() {
        let ids = model.items.map(\.id)
        guard !ids.isEmpty else { return }
        let previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = ids.count == 1 ? "Discard this capture?" : "Discard all \(ids.count) captures?"
        alert.informativeText = "Captures that haven't been saved will be lost."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        // Hand focus back to whatever the user was working in.
        if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        guard confirmed else { return }
        for id in ids { model.remove(id) }
        refresh()
    }
}

// MARK: - SwiftUI

struct CaptureTrayActions {
    let edit: (UUID) -> Void
    let save: (UUID) -> Void
    let copy: (UUID) -> Void
    let discard: (UUID) -> Void
    let saveAll: () -> Void
    let discardAll: () -> Void
    let toggleExpanded: () -> Void

    static let none = CaptureTrayActions(
        edit: { _ in }, save: { _ in }, copy: { _ in }, discard: { _ in },
        saveAll: {}, discardAll: {}, toggleExpanded: {}
    )
}

struct CaptureTrayView: View {
    let items: [CaptureTrayItem]
    let expanded: Bool
    let saveLabel: String
    let saveAllLabel: String
    let actions: CaptureTrayActions

    static let empty = CaptureTrayView(
        items: [], expanded: true, saveLabel: "Save", saveAllLabel: "Save All", actions: .none
    )

    private typealias Metrics = CaptureTrayLayout

    var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            if expanded {
                header
                list
            } else {
                collapsed
            }
        }
        .padding(Metrics.cardPadding)
        .frame(
            width: Metrics.cardWidth,
            height: Metrics.cardHeight(count: items.count, expanded: expanded),
            alignment: .top
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .padding(Metrics.shadowPadding)
    }

    private var title: String {
        items.count == 1 ? "1 Capture" : "\(items.count) Captures"
    }

    // MARK: Expanded

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.down.right")
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(saveAllLabel, action: actions.saveAll)
                .controlSize(.small)
                .help("Save every capture in the tray")
            iconButton("trash", "Discard All", action: actions.discardAll)
            iconButton("chevron.down", "Collapse Tray", action: actions.toggleExpanded)
        }
        .frame(height: Metrics.headerHeight)
    }

    private var list: some View {
        ScrollView(.vertical) {
            VStack(spacing: Metrics.rowSpacing) {
                ForEach(items) { item in
                    row(item)
                }
            }
        }
        .scrollDisabled(!Metrics.needsScrolling(count: items.count))
        .scrollIndicators(Metrics.needsScrolling(count: items.count) ? .automatic : .never)
        .frame(height: Metrics.listHeight(count: items.count))
    }

    private func row(_ item: CaptureTrayItem) -> some View {
        HStack(spacing: 10) {
            thumbnail(item.thumbnail)
                .frame(width: Metrics.thumbnailSize.width, height: Metrics.thumbnailSize.height)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(item.sizeLabel)
                        .lineLimit(1)
                    if item.onClipboard {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("On the clipboard")
                            .accessibilityLabel("On the clipboard")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 2) {
                    iconButton("pencil.tip.crop.circle", "Edit…", prominent: true) { actions.edit(item.id) }
                    iconButton("square.and.arrow.down", saveLabel) { actions.save(item.id) }
                    iconButton("doc.on.doc", "Copy") { actions.copy(item.id) }
                    ShareButton(image: { item.capture.image }, scale: item.capture.scale, labeled: false)
                        .buttonStyle(.borderless)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 26, height: 24)
                    iconButton("xmark.circle", "Discard") { actions.discard(item.id) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.rowHeight)
    }

    private func thumbnail(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }

    // MARK: Collapsed

    /// The whole card is one button: click anywhere to open the drawer.
    private var collapsed: some View {
        Button(action: actions.toggleExpanded) {
            HStack(spacing: 12) {
                stackedThumbnails
                    .frame(width: 84, height: Metrics.collapsedHeight)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("Click to show")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
            .frame(height: Metrics.collapsedHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show Captures")
        .accessibilityLabel("\(title). Show captures")
    }

    /// The newest few thumbnails fanned like a little pile of photos.
    private var stackedThumbnails: some View {
        // Back of the pile first, so the newest draws on top.
        let pile: [(offset: Int, element: CaptureTrayItem)] =
            Array(Array(items.prefix(3).enumerated()).reversed())
        return ZStack {
            ForEach(pile, id: \.element.id) { entry in
                thumbnail(entry.element.thumbnail)
                    .frame(width: 68, height: 44)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .offset(x: CGFloat(entry.offset) * 5, y: CGFloat(entry.offset) * -4)
                    .opacity(entry.offset == 0 ? 1 : 0.85)
            }
        }
        .offset(x: -5, y: 4)
    }

    // MARK: Pieces

    private func iconButton(
        _ symbol: String,
        _ label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(prominent ? Color.accentColor : Color.primary)
        .help(label)
        .accessibilityLabel(label)
    }
}
