import Testing
import AppKit
@testable import NiceShot

private func trayItem(onClipboard: Bool = false) -> CaptureTrayItem {
    CaptureTrayItem(id: UUID(), capture: makeTestCapture(), thumbnail: NSImage(), onClipboard: onClipboard)
}

struct CaptureRoutingTests {
    @Test func loneCaptureGetsClassicPanel() {
        #expect(CaptureRouting.destination(panelShowing: false, trayShowing: false) == .panel)
    }

    @Test func secondCaptureStartsTray() {
        #expect(CaptureRouting.destination(panelShowing: true, trayShowing: false) == .startTray)
    }

    @Test func laterCapturesJoinTray() {
        #expect(CaptureRouting.destination(panelShowing: false, trayShowing: true) == .tray)
        // Never a panel and a tray at once, but the tray wins if it happens.
        #expect(CaptureRouting.destination(panelShowing: true, trayShowing: true) == .tray)
    }
}

struct CaptureTrayItemsTests {
    @Test func newestFirstAndOldestFirst() {
        var model = CaptureTrayItems()
        let a = trayItem(), b = trayItem(), c = trayItem()
        model.add(a)
        model.add(b)
        model.add(c)
        #expect(model.items.map(\.id) == [c.id, b.id, a.id])
        #expect(model.oldestFirst.map(\.id) == [a.id, b.id, c.id])
        #expect(model.count == 3)
    }

    @Test func removeByID() {
        var model = CaptureTrayItems()
        let a = trayItem(), b = trayItem()
        model.add(a)
        model.add(b)
        #expect(model.remove(a.id)?.id == a.id)
        #expect(model.items.map(\.id) == [b.id])
        // Removing twice (e.g. a late save after a discard) is harmless.
        #expect(model.remove(a.id) == nil)
        #expect(model.remove(b.id) != nil)
        #expect(model.isEmpty)
    }

    @Test func autoCopiedCaptureTakesTheClipboardMark() {
        var model = CaptureTrayItems()
        let first = trayItem(onClipboard: true)
        let second = trayItem(onClipboard: true)
        model.add(first)
        model.add(second)
        #expect(model.item(second.id)?.onClipboard == true)
        #expect(model.item(first.id)?.onClipboard == false)
    }

    @Test func uncopiedCaptureLeavesClipboardMark() {
        var model = CaptureTrayItems()
        let copied = trayItem(onClipboard: true)
        model.add(copied)
        model.add(trayItem(onClipboard: false))
        #expect(model.item(copied.id)?.onClipboard == true)
    }

    @Test func clipboardChangeClearsEveryMark() {
        var model = CaptureTrayItems()
        model.add(trayItem(onClipboard: true))
        model.add(trayItem())
        model.clipboardChanged()
        #expect(model.items.allSatisfy { !$0.onClipboard })
    }
}

struct CaptureTrayLayoutTests {
    typealias L = CaptureTrayLayout

    @Test func listGrowsPerRowUpToTheLimit() {
        #expect(L.listHeight(count: 1) == L.rowHeight)
        #expect(L.listHeight(count: 2) == L.rowHeight * 2 + L.rowSpacing)
        #expect(L.listHeight(count: 4) == L.rowHeight * 4 + L.rowSpacing * 3)
        #expect(!L.needsScrolling(count: 4))
    }

    @Test func longListsScrollWithAPeekingRow() {
        #expect(L.needsScrolling(count: 5))
        let capped = L.listHeight(count: 5)
        #expect(capped > L.listHeight(count: 4))
        #expect(capped < L.rowHeight * 5 + L.rowSpacing * 4)
        // Any number of captures keeps the tray the same height.
        #expect(L.listHeight(count: 40) == capped)
    }

    @Test func collapsedTrayIsCompactAndConstant() {
        let collapsed = L.windowSize(count: 2, expanded: false)
        #expect(collapsed == L.windowSize(count: 30, expanded: false))
        #expect(collapsed.height < L.windowSize(count: 2, expanded: true).height)
    }

    @Test func windowAddsShadowMargin() {
        let size = L.windowSize(count: 3, expanded: true)
        #expect(size.width == L.cardWidth + L.shadowPadding * 2)
        #expect(size.height == L.cardHeight(count: 3, expanded: true) + L.shadowPadding * 2)
    }

    @Test func trayFitsOnSmallScreens() {
        // Must fit comfortably on a 13" MacBook Air's 900-pt-tall usable area.
        #expect(L.windowSize(count: 100, expanded: true).height < 500)
    }

    @Test func panelAndTrayShareTheCorner() {
        let vf = CGRect(x: 0, y: 80, width: 1440, height: 800)
        let size = CGSize(width: 370, height: 200)
        let origin = FloatingPanelPlacement.origin(windowSize: size, visibleFrame: vf)
        #expect(origin.x + size.width == vf.maxX - FloatingPanelPlacement.margin)
        #expect(origin.y == vf.minY + FloatingPanelPlacement.margin)
    }
}

struct ThumbnailTests {
    @Test func fitsWithinBoundsKeepingAspect() {
        let size = Thumbnail.fittedPixelSize(
            for: CGSize(width: 5120, height: 2880),
            maxPixels: CGSize(width: 600, height: 380)
        )
        #expect(size == CGSize(width: 600, height: 338))
    }

    @Test func tallImagesLimitedByHeight() {
        let size = Thumbnail.fittedPixelSize(
            for: CGSize(width: 400, height: 2000),
            maxPixels: CGSize(width: 600, height: 380)
        )
        #expect(size == CGSize(width: 76, height: 380))
    }

    @Test func neverUpscalesOrCollapses() {
        #expect(Thumbnail.fittedPixelSize(for: CGSize(width: 50, height: 40), maxPixels: CGSize(width: 600, height: 380))
            == CGSize(width: 50, height: 40))
        #expect(Thumbnail.fittedPixelSize(for: CGSize(width: 10_000, height: 1), maxPixels: CGSize(width: 100, height: 100))
            == CGSize(width: 100, height: 1))
        #expect(Thumbnail.fittedPixelSize(for: .zero, maxPixels: CGSize(width: 100, height: 100))
            == CGSize(width: 1, height: 1))
    }

    @Test func makeDownscalesPixelsAndReportsPoints() throws {
        let image = makeTestImage(width: 2000, height: 1000)
        let thumb = Thumbnail.make(from: image, maxPoints: CGSize(width: 96, height: 60))
        // 2× pixels for Retina, sized in points.
        #expect(thumb.size == CGSize(width: 96, height: 48))
        let rep = try #require(thumb.representations.first)
        #expect(rep.pixelsWide == 192)
        #expect(rep.pixelsHigh == 96)
    }

    @Test func smallImagesAreNotCopied() {
        let image = makeTestImage(width: 100, height: 50)
        let thumb = Thumbnail.make(from: image, maxPoints: CGSize(width: 300, height: 190))
        #expect(thumb.size == CGSize(width: 50, height: 25))
    }
}
