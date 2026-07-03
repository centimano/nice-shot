import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultRegion = Hotkey(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: UInt32(controlKey | shiftKey))
    static let defaultWindow = Hotkey(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: UInt32(controlKey | shiftKey))
    static let defaultFullScreen = Hotkey(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(controlKey | shiftKey))
    static let defaultScreenDraw = Hotkey(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(controlKey | shiftKey))
    static let defaultZoom = Hotkey(keyCode: UInt32(kVK_ANSI_Z), carbonModifiers: UInt32(controlKey | shiftKey))

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Build from a key-down event; requires ⌘, ⌃, or ⌥ so plain typing can't
    /// become a global hotkey.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
    }

    var nsModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var display: String {
        var out = ""
        if carbonModifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + keyName
    }

    var keyName: String {
        Hotkey.keyNames[keyCode] ?? "Key \(keyCode)"
    }

    /// Character usable as an NSMenuItem key equivalent, when one exists.
    var menuKeyEquivalent: String? {
        let name = keyName
        if name.count == 1, let ch = name.first, ch.isASCII { return name.lowercased() }
        if keyCode == UInt32(kVK_Space) { return " " }
        return nil
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

/// What happens to a fresh capture (OVR-002 in the original spec).
enum PostCaptureAction: String, CaseIterable, Identifiable {
    case panel
    case copy
    case save
    case edit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .panel: "Show the capture panel"
        case .copy: "Copy to the clipboard"
        case .save: "Save"
        case .edit: "Open the editor"
        }
    }
}

/// UserDefaults-backed app settings shared across the app.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let hotkeysChanged = Notification.Name("NiceShot.hotkeysChanged")

    @Published var regionHotkey: Hotkey {
        didSet { store(regionHotkey, key: "regionHotkey"); notifyHotkeysChanged() }
    }
    @Published var windowHotkey: Hotkey {
        didSet { store(windowHotkey, key: "windowHotkey"); notifyHotkeysChanged() }
    }
    @Published var fullScreenHotkey: Hotkey {
        didSet { store(fullScreenHotkey, key: "fullScreenHotkey"); notifyHotkeysChanged() }
    }
    @Published var screenDrawHotkey: Hotkey {
        didSet { store(screenDrawHotkey, key: "screenDrawHotkey"); notifyHotkeysChanged() }
    }
    @Published var zoomHotkey: Hotkey {
        didSet { store(zoomHotkey, key: "zoomHotkey"); notifyHotkeysChanged() }
    }
    @Published var showCursor: Bool {
        didSet { defaults.set(showCursor, forKey: "showCursor") }
    }
    @Published var playCaptureSound: Bool {
        didSet { defaults.set(playCaptureSound, forKey: "playCaptureSound") }
    }
    @Published var autoCopy: Bool {
        didSet { defaults.set(autoCopy, forKey: "autoCopy") }
    }
    @Published var postCaptureAction: PostCaptureAction {
        didSet { defaults.set(postCaptureAction.rawValue, forKey: "postCaptureAction") }
    }
    @Published var askWhereToSave: Bool {
        didSet { defaults.set(askWhereToSave, forKey: "askWhereToSave") }
    }
    @Published var saveFolderPath: String {
        didSet { defaults.set(saveFolderPath, forKey: "saveFolderPath") }
    }
    @Published var saveFormat: ImageFormat {
        didSet { defaults.set(saveFormat.rawValue, forKey: "saveFormat") }
    }
    @Published var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: "jpegQuality") }
    }
    /// Mirrors SMAppService state; mutate via `setLaunchAtLogin`.
    @Published private(set) var launchAtLogin: Bool

    var saveFolder: URL {
        URL(fileURLWithPath: (saveFolderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    private let defaults = UserDefaults.standard

    private init() {
        regionHotkey = Self.load("regionHotkey") ?? .defaultRegion
        windowHotkey = Self.load("windowHotkey") ?? .defaultWindow
        fullScreenHotkey = Self.load("fullScreenHotkey") ?? .defaultFullScreen
        screenDrawHotkey = Self.load("screenDrawHotkey") ?? .defaultScreenDraw
        zoomHotkey = Self.load("zoomHotkey") ?? .defaultZoom
        showCursor = defaults.bool(forKey: "showCursor")
        playCaptureSound = defaults.object(forKey: "playCaptureSound") as? Bool ?? true
        autoCopy = defaults.bool(forKey: "autoCopy")
        postCaptureAction = PostCaptureAction(rawValue: defaults.string(forKey: "postCaptureAction") ?? "") ?? .panel
        askWhereToSave = defaults.object(forKey: "askWhereToSave") as? Bool ?? true
        saveFolderPath = defaults.string(forKey: "saveFolderPath") ?? "~/Desktop"
        saveFormat = ImageFormat(rawValue: defaults.string(forKey: "saveFormat") ?? "") ?? .png
        jpegQuality = defaults.object(forKey: "jpegQuality") as? Double ?? 0.85
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func store(_ hotkey: Hotkey, key: String) {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(_ key: String) -> Hotkey? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private func notifyHotkeysChanged() {
        NotificationCenter.default.post(name: Self.hotkeysChanged, object: nil)
    }
}
