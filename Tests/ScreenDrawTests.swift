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

/// Keeping the screen-draw strip clear of a MacBook's camera notch.
struct NotchPlacementTests {
    // A 14" MacBook Pro at its default resolution: 1512 pt wide, notch
    // ~186 pt wide and 32 pt tall, centered.
    private let notch = NotchGeometry(screenWidth: 1512, leftAreaWidth: 663, rightAreaWidth: 663, height: 32)!
    private let screen = CGSize(width: 1512, height: 982)

    @Test func noNotchMeansNoGeometry() {
        #expect(NotchGeometry(screenWidth: 1512, leftAreaWidth: 663, rightAreaWidth: 663, height: 0) == nil)
        #expect(NotchGeometry(screenWidth: 1000, leftAreaWidth: 600, rightAreaWidth: 600, height: 32) == nil)
    }

    @Test func notchSpansTheGapBetweenTheSideAreas() {
        #expect(notch.minX == 663)
        #expect(notch.maxX == 849)
        #expect(notch.height == 32)
    }

    @Test func halvesFlankTheNotchWhenTheyFit() {
        let f = NotchPlacement.frames(
            left: CGSize(width: 450, height: 40),
            right: CGSize(width: 360, height: 40),
            container: screen,
            notch: notch
        )
        #expect(f.flanking)
        // Neither half overlaps the notch, both stay on screen.
        #expect(f.left.maxX <= notch.minX - NotchPlacement.gap)
        #expect(f.right.minX >= notch.maxX + NotchPlacement.gap)
        #expect(f.left.minX >= NotchPlacement.margin)
        #expect(f.right.maxX <= screen.width - NotchPlacement.margin)
        // Same top position as the single strip on other screens.
        #expect(f.left.minY == NotchPlacement.topInset)
        #expect(f.right.minY == NotchPlacement.topInset)
    }

    @Test func halvesDropBelowTheNotchWhenTheSidesAreTooNarrow() {
        // A "larger text" resolution: much less room beside the notch.
        let tight = NotchGeometry(screenWidth: 1024, leftAreaWidth: 420, rightAreaWidth: 420, height: 32)!
        let f = NotchPlacement.frames(
            left: CGSize(width: 450, height: 40),
            right: CGSize(width: 360, height: 40),
            container: CGSize(width: 1024, height: 665),
            notch: tight
        )
        #expect(!f.flanking)
        #expect(f.left.minY >= tight.height)
        #expect(f.right.minY >= tight.height)
        #expect(f.right.minX >= f.left.maxX)
        #expect(f.left.minX >= NotchPlacement.margin)
    }

    @Test func shorterHalfIsCenteredOnTheTallerOne() {
        let f = NotchPlacement.frames(
            left: CGSize(width: 300, height: 40),
            right: CGSize(width: 300, height: 30),
            container: screen,
            notch: notch
        )
        #expect(f.left.midY == f.right.midY)
    }
}
