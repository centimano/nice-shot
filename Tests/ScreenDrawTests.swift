import Testing
import AppKit
@testable import NiceShot

/// Screen draw mode's key handling is a pure mapping, so the whole state
/// machine of "which key does what, and when" is testable headlessly.
struct ScreenDrawKeysTests {
    private func command(
        keyCode: UInt16 = 0,
        _ modifiers: NSEvent.ModifierFlags = [],
        _ characters: String? = nil,
        editing: Bool = false
    ) -> ScreenDrawCommand? {
        ScreenDrawKeys.command(
            keyCode: keyCode,
            modifiers: modifiers,
            characters: characters,
            isEditingText: editing
        )
    }

    @Test func escExits() {
        #expect(command(keyCode: 53) == .exit)
    }

    @Test func escWhileTypingEndsTextEditingInstead() {
        #expect(command(keyCode: 53, editing: true) == .endTextEditing)
    }

    @Test func typingIsLeftToTheTextField() {
        // While editing text, every key but Esc must pass through untouched
        // — including the mode's own shortcuts.
        #expect(command([], "p", editing: true) == nil)
        #expect(command(.command, "c", editing: true) == nil)
        #expect(command(keyCode: 51, editing: true) == nil)
    }

    @Test func commandShortcuts() {
        #expect(command(.command, "z") == .undo)
        #expect(command([.command, .shift], "z") == .redo)
        #expect(command(.command, "c") == .copy)
        #expect(command(.command, "s") == .save)
        #expect(command(.command, "e") == .openEditor)
    }

    @Test func unownedCommandKeysPassThrough() {
        #expect(command(.command, "q") == nil)
        #expect(command(.command, "w") == nil)
        #expect(command([.command, .option], "c") == nil, "extra modifiers mean it isn't our shortcut")
        #expect(command([.command, .control], "s") == nil)
    }

    @Test func deleteKeyDeletesSelection() {
        #expect(command(keyCode: 51) == .deleteSelection)
    }

    @Test func singleLetterToolShortcuts() {
        #expect(command([], "v") == .selectTool(.select))
        #expect(command([], "p") == .selectTool(.pen))
        #expect(command([], "h") == .selectTool(.highlighter))
        #expect(command([], "a") == .selectTool(.arrow))
        #expect(command([], "l") == .selectTool(.line))
        #expect(command([], "b") == .selectTool(.box))
        #expect(command([], "e") == .selectTool(.ellipse))
        #expect(command([], "t") == .selectTool(.text))
    }

    @Test func boardKeysSwapTheBackground() {
        #expect(command([], "w") == .board(.white))
        #expect(command([], "k") == .board(.black))
    }

    @Test func boardKeysPassThroughWhileTyping() {
        #expect(command([], "w", editing: true) == nil)
        #expect(command([], "k", editing: true) == nil)
    }

    @Test func shiftedLettersStillSelectTools() {
        #expect(command(.shift, "P") == .selectTool(.pen))
    }

    @Test func lettersWithOtherModifiersPassThrough() {
        #expect(command(.option, "p") == nil)
        #expect(command(.control, "a") == nil)
    }

    @Test func unmappedKeysPassThrough() {
        #expect(command([], "q") == nil)
        #expect(command([], "1") == nil)
        #expect(command(keyCode: 126) == nil, "arrow keys are not owned by the mode")
    }
}
