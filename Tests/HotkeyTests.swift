import Testing
import AppKit
import Carbon.HIToolbox
@testable import SuperDuperScreenshot

@MainActor
struct HotkeyTests {
    @Test func defaultShortcutsDisplay() {
        #expect(Hotkey.defaultRegion.display == "⌃⇧4")
        #expect(Hotkey.defaultWindow.display == "⌃⇧5")
        #expect(Hotkey.defaultFullScreen.display == "⌃⇧3")
    }

    @Test func displayUsesStandardModifierOrder() {
        let hotkey = Hotkey(
            keyCode: UInt32(kVK_ANSI_S),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        #expect(hotkey.display == "⌃⌥⇧⌘S")
    }

    @Test func keyNamesForSpecialKeys() {
        #expect(Hotkey(keyCode: 123, carbonModifiers: 0).keyName == "←")
        #expect(Hotkey(keyCode: 49, carbonModifiers: 0).keyName == "Space")
        #expect(Hotkey(keyCode: 122, carbonModifiers: 0).keyName == "F1")
    }

    @Test func unknownKeyCodeFallsBack() {
        #expect(Hotkey(keyCode: 200, carbonModifiers: 0).keyName == "Key 200")
    }

    @Test func menuKeyEquivalents() {
        #expect(Hotkey(keyCode: 0, carbonModifiers: 0).menuKeyEquivalent == "a")
        #expect(Hotkey(keyCode: 21, carbonModifiers: 0).menuKeyEquivalent == "4")
        #expect(Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: 0).menuKeyEquivalent == " ")
        #expect(Hotkey(keyCode: 122, carbonModifiers: 0).menuKeyEquivalent == nil, "F-keys have no menu equivalent")
        #expect(Hotkey(keyCode: 123, carbonModifiers: 0).menuKeyEquivalent == nil, "arrows have no menu equivalent")
    }

    @Test func nsModifierMapping() {
        let hotkey = Hotkey(keyCode: 0, carbonModifiers: UInt32(cmdKey | controlKey))
        #expect(hotkey.nsModifiers == [.command, .control])
    }

    @Test func codableRoundTrip() throws {
        let original = Hotkey(keyCode: 21, carbonModifiers: UInt32(controlKey | shiftKey))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        #expect(decoded == original)
    }

    @Test func initFromEventCapturesKeyAndModifiers() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "4",
            charactersIgnoringModifiers: "4",
            isARepeat: false,
            keyCode: 21
        ))
        let hotkey = try #require(Hotkey(event: event))
        #expect(hotkey.keyCode == 21)
        #expect(hotkey.display == "⌃⇧4")
    }

    @Test func initFromEventRejectsShiftOnly() throws {
        // Shift alone would turn ordinary typing into a global hotkey.
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "A",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        #expect(Hotkey(event: event) == nil)
    }

    @Test func initFromEventRejectsNoModifiers() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        #expect(Hotkey(event: event) == nil)
    }
}
