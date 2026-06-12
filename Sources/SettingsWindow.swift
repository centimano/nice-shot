import AppKit
import SwiftUI

/// Keeps the app a menu-bar accessory until a real window (editor, settings)
/// is open, then shows a Dock icon so ⌘-Tab and window ordering work.
@MainActor
enum ActivationPolicy {
    private static var retainCount = 0

    static func retain() {
        retainCount += 1
        if retainCount == 1 {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func release() {
        retainCount = max(0, retainCount - 1)
        if retainCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "Nice Shot Settings"
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            // Tall enough to show every section without scrolling, capped to
            // the screen. Afterwards the frame autosaves, so a user resize is
            // restored the next time Settings opens.
            let height = min(700, (NSScreen.main?.visibleFrame.height ?? 800) - 80)
            w.setContentSize(NSSize(width: 480, height: height))
            w.center()
            w.setFrameAutosaveName("NiceShotSettings")
            window = w
            ActivationPolicy.retain()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        HotkeyManager.shared.isPaused = false
        ActivationPolicy.release()
    }
}

// MARK: - Settings UI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                HotkeyRecorder(title: "Capture Region", hotkey: $settings.regionHotkey, defaultValue: .defaultRegion)
                HotkeyRecorder(title: "Capture Window", hotkey: $settings.windowHotkey, defaultValue: .defaultWindow)
                HotkeyRecorder(title: "Capture Full Screen", hotkey: $settings.fullScreenHotkey, defaultValue: .defaultFullScreen)
            }

            Section("Capture") {
                Toggle("Show mouse cursor in captures", isOn: $settings.showCursor)
                Toggle("Play shutter sound", isOn: $settings.playCaptureSound)
                Toggle("Copy new captures to the clipboard", isOn: $settings.autoCopy)
                Picker("After each capture", selection: $settings.postCaptureAction) {
                    ForEach(PostCaptureAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }

            Section("Saving") {
                Toggle("Ask where to save each time", isOn: $settings.askWhereToSave)
                if !settings.askWhereToSave {
                    HStack {
                        Text("Save to")
                        Spacer()
                        Text(settings.saveFolderPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                    }
                }
                Picker("Format", selection: $settings.saveFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                if settings.saveFormat == .jpeg {
                    HStack {
                        Text("JPEG quality")
                        Slider(value: $settings.jpegQuality, in: 0.3...1.0)
                        Text("\(Int(settings.jpegQuality * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { enabled in
                do {
                    try settings.setLaunchAtLogin(enabled)
                    loginError = nil
                } catch {
                    loginError = "Could not update login item: \(error.localizedDescription) "
                        + "Try moving the app to /Applications first."
                }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        settings.saveFolderPath = path.hasPrefix(home)
            ? path.replacingOccurrences(of: home, with: "~", options: .anchored)
            : path
    }
}

/// Click to record a new shortcut; Esc cancels. Global hotkeys are paused
/// while recording so the combo being typed doesn't trigger a capture.
private struct HotkeyRecorder: View {
    let title: String
    @Binding var hotkey: Hotkey
    let defaultValue: Hotkey

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "Press shortcut…" : hotkey.display) {
                recording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 110)
            Button {
                hotkey = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(hotkey == defaultValue)
            .help("Reset to default")
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        HotkeyManager.shared.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels
                stopRecording()
                return nil
            }
            if let newHotkey = Hotkey(event: event) {
                hotkey = newHotkey
                stopRecording()
            }
            return nil // swallow keystrokes while recording
        }
    }

    private func stopRecording() {
        recording = false
        HotkeyManager.shared.isPaused = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
