import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator = CaptureCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "Nice Shot"
        )
        statusItem = item

        applyHotkeySettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeysChanged),
            name: AppSettings.hotkeysChanged,
            object: nil
        )
    }

    @objc private func hotkeysChanged() {
        applyHotkeySettings()
    }

    /// Opening the app while it's already running (e.g. double-clicking it in
    /// Finder) shows Settings — otherwise a menu-bar-only app appears to do
    /// nothing, which reads as "broken".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            SettingsWindowController.shared.show()
        }
        return true
    }

    /// (Re)registers global hotkeys and rebuilds the status menu so its
    /// displayed key equivalents stay in sync with Settings.
    private func applyHotkeySettings() {
        let settings = AppSettings.shared
        let manager = HotkeyManager.shared
        manager.unregisterAll()
        manager.register(
            keyCode: settings.regionHotkey.keyCode,
            modifiers: settings.regionHotkey.carbonModifiers
        ) { [weak self] in self?.coordinator.captureRegion() }
        manager.register(
            keyCode: settings.windowHotkey.keyCode,
            modifiers: settings.windowHotkey.carbonModifiers
        ) { [weak self] in self?.coordinator.captureWindow() }
        manager.register(
            keyCode: settings.fullScreenHotkey.keyCode,
            modifiers: settings.fullScreenHotkey.carbonModifiers
        ) { [weak self] in self?.coordinator.captureFullScreen() }
        manager.register(
            keyCode: settings.screenDrawHotkey.keyCode,
            modifiers: settings.screenDrawHotkey.carbonModifiers
        ) { [weak self] in self?.coordinator.drawOnScreen() }

        statusItem?.menu = buildStatusMenu()
    }

    // MARK: - Status menu

    private func buildStatusMenu() -> NSMenu {
        let settings = AppSettings.shared
        let menu = NSMenu()

        func add(_ title: String, _ action: Selector, hotkey: Hotkey? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            if let hotkey, let key = hotkey.menuKeyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = hotkey.nsModifiers
            }
            item.target = self
            menu.addItem(item)
        }

        add("Capture Region", #selector(captureRegion), hotkey: settings.regionHotkey)
        add("Capture Window", #selector(captureWindow), hotkey: settings.windowHotkey)
        add("Capture Full Screen", #selector(captureFullScreen), hotkey: settings.fullScreenHotkey)
        add("Draw on Screen", #selector(drawOnScreen), hotkey: settings.screenDrawHotkey)

        let timed = NSMenuItem(title: "Timed Capture", action: nil, keyEquivalent: "")
        let timedMenu = NSMenu()
        for secs in [3, 5, 10] {
            let item = NSMenuItem(title: "\(secs) Seconds", action: #selector(timedCapture(_:)), keyEquivalent: "")
            item.tag = secs
            item.target = self
            timedMenu.addItem(item)
        }
        timed.submenu = timedMenu
        menu.addItem(timed)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let about = NSMenuItem(
            title: "About Nice Shot",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Nice Shot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    // MARK: - Main menu (key equivalents for editor windows & text fields)

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Nice Shot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: - Actions

    @objc private func captureRegion() { coordinator.captureRegion() }
    @objc private func captureWindow() { coordinator.captureWindow() }
    @objc private func captureFullScreen() { coordinator.captureFullScreen() }
    @objc private func drawOnScreen() { coordinator.drawOnScreen() }
    @objc private func timedCapture(_ sender: NSMenuItem) { coordinator.timedCapture(seconds: sender.tag) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }

    /// A menu-bar accessory app isn't active when its menu is used, so the
    /// standard About panel would open behind the frontmost app. Activate
    /// first so it comes to the foreground.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
