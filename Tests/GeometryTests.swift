import Testing
import Foundation
@testable import SuperDuperScreenshot

struct GeometryTests {
    // MARK: CGRect(points:) — drag rectangles must normalize in any direction

    @Test func rectFromPointsNormalizes() {
        let rect = CGRect(points: CGPoint(x: 100, y: 80), CGPoint(x: 20, y: 10))
        #expect(rect == CGRect(x: 20, y: 10, width: 80, height: 70))
    }

    @Test func rectFromIdenticalPointsIsEmpty() {
        let rect = CGRect(points: CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5))
        #expect(rect == CGRect(x: 5, y: 5, width: 0, height: 0))
    }

    // MARK: Point→pixel crop conversion

    @Test func pixelRectScalesAndRounds() {
        let rect = CGRect(x: 10.6, y: 20.3, width: 100.4, height: 50.5)
        let pixels = CaptureEngine.pixelRect(for: rect, scale: 2)
        #expect(pixels == CGRect(x: 21, y: 40, width: 201, height: 101))
    }

    @Test func pixelRectIdentityAtScale1() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(CaptureEngine.pixelRect(for: rect, scale: 1) == rect)
    }

    // MARK: Global CG → screen-local coordinates (window picker)

    @Test func localRectOnPrimaryScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let local = ScreenGeometry.localRect(
            globalCG: CGRect(x: 100, y: 200, width: 300, height: 400),
            screenFrame: screen,
            primaryHeight: 1080
        )
        #expect(local == CGRect(x: 100, y: 200, width: 300, height: 400))
    }

    @Test func localRectOnSecondaryScreenToTheRight() {
        // A 1440×900 display to the right of a 1920×1080 primary.
        let screen = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        let local = ScreenGeometry.localRect(
            globalCG: CGRect(x: 2000, y: 300, width: 500, height: 400),
            screenFrame: screen,
            primaryHeight: 1080
        )
        #expect(local == CGRect(x: 80, y: 120, width: 500, height: 400))
    }

    @Test func localRectOnScreenAboveAndLeft() {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let local = ScreenGeometry.localRect(
            globalCG: CGRect(x: -1000, y: 100, width: 400, height: 300),
            screenFrame: screen,
            primaryHeight: 1080
        )
        #expect(local == CGRect(x: 440, y: 120, width: 400, height: 300))
    }

    // MARK: Small clamping helpers

    @Test func clampedWithinRange() {
        #expect(CGFloat(5).clamped(0, 10) == 5)
        #expect(CGFloat(-3).clamped(0, 10) == 0)
        #expect(CGFloat(42).clamped(0, 10) == 10)
    }

    @Test func clampedDegenerateRangeReturnsSelf() {
        #expect(CGFloat(7).clamped(10, 0) == 7)
    }

    @Test func rectClampedToImageSize() {
        let clamped = CGRect(x: -50, y: -50, width: 1000, height: 1000)
            .clamped(to: CGSize(width: 200, height: 100))
        #expect(clamped == CGRect(x: 0, y: 0, width: 200, height: 100))
    }
}
