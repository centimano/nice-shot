import Testing
import AppKit
@testable import NiceShot

/// Frozen zoom geometry is pure math, so the interesting behaviors —
/// zoom-toward-cursor, pan clamping, viewport cropping — are all testable
/// headlessly.
struct ZoomMathTests {
    private let imageSize = CGSize(width: 3840, height: 2160)

    @Test func magnificationClampsToRange() {
        #expect(ZoomMath.clamped(0.2) == 1)
        #expect(ZoomMath.clamped(1) == 1)
        #expect(ZoomMath.clamped(3.5) == 3.5)
        #expect(ZoomMath.clamped(64) == 8)
    }

    @Test func magnificationStepsAreExponential() {
        #expect(ZoomMath.magnification(after: 1, from: 2) == 4)
        #expect(ZoomMath.magnification(after: -1, from: 4) == 2)
        #expect(ZoomMath.magnification(after: -3, from: 2) == 1, "clamps at 1×")
        #expect(ZoomMath.magnification(after: 5, from: 4) == 8, "clamps at 8×")
    }

    @Test func fullImageVisibleAtOneRegardlessOfFocus() {
        for focus in [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)] {
            let rect = ZoomMath.visibleRect(imageSize: imageSize, magnification: 1, focus: focus)
            #expect(rect == CGRect(origin: .zero, size: imageSize))
        }
    }

    @Test func pointUnderCursorStaysFixedAcrossZoom() {
        // The image point under the cursor must be focus × imageSize at any
        // magnification — that's what makes scrolling zoom toward the cursor.
        let focus = CGPoint(x: 0.3, y: 0.7)
        for m: CGFloat in [1, 1.5, 2, 4, 8] {
            let rect = ZoomMath.visibleRect(imageSize: imageSize, magnification: m, focus: focus)
            let pointUnderCursor = CGPoint(
                x: rect.minX + focus.x * rect.width,
                y: rect.minY + focus.y * rect.height
            )
            #expect(abs(pointUnderCursor.x - focus.x * imageSize.width) < 0.001)
            #expect(abs(pointUnderCursor.y - focus.y * imageSize.height) < 0.001)
        }
    }

    @Test func panClampsAtEdges() {
        let atOrigin = ZoomMath.visibleRect(imageSize: imageSize, magnification: 4, focus: .zero)
        #expect(atOrigin.origin == .zero)

        let atFarCorner = ZoomMath.visibleRect(imageSize: imageSize, magnification: 4, focus: CGPoint(x: 1, y: 1))
        #expect(abs(atFarCorner.maxX - imageSize.width) < 0.001)
        #expect(abs(atFarCorner.maxY - imageSize.height) < 0.001)

        let outOfRange = ZoomMath.visibleRect(imageSize: imageSize, magnification: 4, focus: CGPoint(x: -2, y: 9))
        #expect(outOfRange.minX == 0)
        #expect(abs(outOfRange.maxY - imageSize.height) < 0.001)
    }

    @Test func viewportKeepsImageAspect() {
        let rect = ZoomMath.visibleRect(imageSize: imageSize, magnification: 3, focus: CGPoint(x: 0.5, y: 0.5))
        let imageAspect = imageSize.width / imageSize.height
        #expect(abs(rect.width / rect.height - imageAspect) < 0.001)
        #expect(abs(rect.width - imageSize.width / 3) < 0.001)
    }

    @Test func cropRectIsIntegralAndInsideTheImage() {
        // An awkward size and magnification produce fractional viewports;
        // the crop rect must still be integral and fully inside the image.
        let odd = CGSize(width: 1437, height: 899)
        for (m, f): (CGFloat, CGPoint) in [
            (1.7, CGPoint(x: 0.33, y: 0.91)),
            (7.9, CGPoint(x: 1, y: 1)),
            (8, CGPoint(x: 0, y: 0.001)),
        ] {
            let crop = ZoomMath.cropRect(imageSize: odd, magnification: m, focus: f)
            #expect(crop == crop.integral)
            #expect(CGRect(origin: .zero, size: odd).contains(crop))
            #expect(crop.width > 0 && crop.height > 0)
        }
    }
}

/// Zoom mode's key handling mirrors screen draw's: a pure mapping.
struct ScreenZoomKeysTests {
    private func command(
        keyCode: UInt16 = 0,
        _ modifiers: NSEvent.ModifierFlags = [],
        _ characters: String? = nil
    ) -> ScreenZoomCommand? {
        ScreenZoomKeys.command(keyCode: keyCode, modifiers: modifiers, characters: characters)
    }

    @Test func escExits() {
        #expect(command(keyCode: 53) == .exit)
    }

    @Test func arrowsZoom() {
        #expect(command(keyCode: 126) == .zoomIn)
        #expect(command(keyCode: 125) == .zoomOut)
    }

    @Test func commandShortcuts() {
        #expect(command(.command, "c") == .copy)
        #expect(command(.command, "s") == .save)
        #expect(command(.command, "e") == .openEditor)
    }

    @Test func toolKeysEnterDrawMode() {
        #expect(command([], "v") == .enterDraw(.select))
        #expect(command([], "p") == .enterDraw(.pen))
        #expect(command([], "d") == .enterDraw(.pen), "D mirrors the draw hotkey")
        #expect(command([], "h") == .enterDraw(.highlighter))
        #expect(command([], "a") == .enterDraw(.arrow))
        #expect(command([], "l") == .enterDraw(.line))
        #expect(command([], "b") == .enterDraw(.box))
        #expect(command([], "e") == .enterDraw(.ellipse))
        #expect(command([], "t") == .enterDraw(.text))
    }

    @Test func unownedKeysPassThrough() {
        #expect(command(.command, "q") == nil)
        #expect(command([.command, .option], "c") == nil, "extra modifiers mean it isn't our shortcut")
        #expect(command(.option, "p") == nil)
        #expect(command([], "w") == nil, "board modes belong to draw mode, not zoom")
        #expect(command([], "1") == nil)
    }
}
