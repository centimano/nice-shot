import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey — works without the
/// Accessibility permission, fires even when another app is frontmost.
@MainActor
final class HotkeyManager {
    typealias Handler = () -> Void

    static let shared = HotkeyManager()
    private init() {}

    /// Suspends all hotkeys (used while the user is recording a new shortcut).
    var isPaused = false

    private var handlers: [UInt32: Handler] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private var nextID: UInt32 = 1

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) {
        installIfNeeded()
        let id = nextID
        nextID += 1
        handlers[id] = handler

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5344_5353) /* 'SDSS' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
        } else {
            NSLog("HotkeyManager: failed to register hotkey (status \(status))")
        }
    }

    fileprivate func fire(id: UInt32) {
        guard !isPaused else { return }
        handlers[id]?()
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Carbon dispatches hotkey events on the main thread.
                MainActor.assumeIsolated {
                    manager.fire(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
}
