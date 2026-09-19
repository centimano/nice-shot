import AppKit
import Testing
import SwiftUI
@testable import NiceShot

struct AnnotationTests {
    // MARK: Bounds

    @Test func boxBoundsEqualRect() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(Annotation.test(.box(rect)).bounds(unit: 1) == rect)
    }

    @Test func arrowBoundsIncludeStrokeWidth() {
        let annotation = Annotation.test(
            .arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 60)),
            strokeWidth: 4
        )
        let expected = CGRect(x: 10, y: 10, width: 100, height: 50).insetBy(dx: -4, dy: -4)
        #expect(annotation.bounds(unit: 1) == expected)
    }

    @Test func penBoundsCoverAllPoints() {
        let annotation = Annotation.test(
            .pen([CGPoint(x: 10, y: 40), CGPoint(x: 60, y: 5), CGPoint(x: 30, y: 90)]),
            strokeWidth: 2
        )
        let bounds = annotation.bounds(unit: 1)
        #expect(bounds.contains(CGPoint(x: 10, y: 40)))
        #expect(bounds.contains(CGPoint(x: 60, y: 5)))
        #expect(bounds.contains(CGPoint(x: 30, y: 90)))
    }

    @Test func stepBoundsCenteredOnPoint() {
        let annotation = Annotation.test(.step(CGPoint(x: 50, y: 50)), fontSize: 22)
        let bounds = annotation.bounds(unit: 1)
        #expect(abs(bounds.midX - 50) < 0.001)
        #expect(abs(bounds.midY - 50) < 0.001)
        let radius = Annotation.stepRadius(fontSize: 22, unit: 1)
        #expect(abs(bounds.width - radius * 2) < 0.001)
    }

    @Test func stepRadiusHasMinimumSize() {
        // Tiny fonts shouldn't produce an unclickable badge.
        #expect(Annotation.stepRadius(fontSize: 5, unit: 1) == 14)
        #expect(Annotation.stepRadius(fontSize: 40, unit: 2) == 68)
    }

    @Test func calloutBoundsIncludeTail() {
        let annotation = Annotation.test(
            .callout(CGRect(x: 10, y: 10, width: 100, height: 40), tail: CGPoint(x: 150, y: 120))
        )
        // CGRect.contains excludes the max edges, so assert the bounds extend
        // exactly to the tail point rather than "containing" it.
        let bounds = annotation.bounds(unit: 1)
        #expect(bounds.maxX == 150)
        #expect(bounds.maxY == 120)
        #expect(bounds.contains(CGPoint(x: 10, y: 10)))
    }

    // MARK: Hit testing

    @Test func penHitsAlongTheStrokeNotItsBoundingBox() {
        // An L-shaped stroke: its bounding box covers a big empty square.
        let pen = Annotation.test(.pen([
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 100),
        ]), strokeWidth: 4)
        #expect(pen.hitTest(CGPoint(x: 2, y: 50), unit: 1))      // on the vertical leg
        #expect(pen.hitTest(CGPoint(x: 60, y: 97), unit: 1))     // on the horizontal leg
        #expect(!pen.hitTest(CGPoint(x: 60, y: 40), unit: 1))    // inside the box, far from ink
    }

    @Test func highlighterHitZoneMatchesItsWiderStroke() {
        let points = [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)]
        let pen = Annotation.test(.pen(points), strokeWidth: 4)
        let marker = Annotation.test(.highlighter(points), strokeWidth: 4)
        // 14 px off the centerline: past the pen's reach (2 + 8 slop) but
        // within the 4× wider marker's (8 + 8 slop).
        let probe = CGPoint(x: 50, y: 64)
        #expect(!pen.hitTest(probe, unit: 1))
        #expect(marker.hitTest(probe, unit: 1))
    }

    @Test func distanceToPolylineUsesNearestSegment() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
        #expect(Annotation.distance(from: CGPoint(x: 5, y: 3), toPolyline: pts) == 3)
        #expect(Annotation.distance(from: CGPoint(x: 13, y: 5), toPolyline: pts) == 3)
        // Beyond the end: distance to the last point, not the extended line.
        #expect(Annotation.distance(from: CGPoint(x: 10, y: 14), toPolyline: pts) == 4)
        #expect(Annotation.distance(from: CGPoint(x: 3, y: 4), toPolyline: [.zero]) == 5)
    }

    @Test func hitTestInsideAndNearEdge() {
        let annotation = Annotation.test(.box(CGRect(x: 20, y: 20, width: 60, height: 40)))
        #expect(annotation.hitTest(CGPoint(x: 50, y: 40), unit: 1))
        // The 8 px grab tolerance makes slightly-outside clicks count…
        #expect(annotation.hitTest(CGPoint(x: 14, y: 20), unit: 1))
        // …but far-away clicks don't.
        #expect(!annotation.hitTest(CGPoint(x: 150, y: 150), unit: 1))
    }

    // MARK: Translation

    @Test func translateMovesEveryShapeKind() throws {
        let delta = CGSize(width: 7, height: -3)

        var box = Annotation.test(.box(CGRect(x: 10, y: 10, width: 20, height: 20)))
        box.translate(by: delta)
        guard case .box(let rect) = box.shape else { Issue.record("shape changed kind"); return }
        #expect(rect == CGRect(x: 17, y: 7, width: 20, height: 20))

        var arrow = Annotation.test(.arrow(start: .zero, end: CGPoint(x: 10, y: 10)))
        arrow.translate(by: delta)
        guard case .arrow(let start, let end) = arrow.shape else { Issue.record("shape changed kind"); return }
        #expect(start == CGPoint(x: 7, y: -3))
        #expect(end == CGPoint(x: 17, y: 7))

        var pen = Annotation.test(.pen([CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]))
        pen.translate(by: delta)
        guard case .pen(let points) = pen.shape else { Issue.record("shape changed kind"); return }
        #expect(points == [CGPoint(x: 8, y: -2), CGPoint(x: 9, y: -1)])

        var callout = Annotation.test(
            .callout(CGRect(x: 0, y: 0, width: 10, height: 10), tail: CGPoint(x: 20, y: 20))
        )
        callout.translate(by: delta)
        guard case .callout(let bubble, let tail) = callout.shape else { Issue.record("shape changed kind"); return }
        #expect(bubble.origin == CGPoint(x: 7, y: -3))
        #expect(tail == CGPoint(x: 27, y: 17))
    }

    // MARK: Handles

    @Test func handleCountsPerShape() {
        func count(_ shape: Annotation.Shape) -> Int {
            Annotation.test(shape).handlePositions(unit: 1).count
        }
        #expect(count(.arrow(start: .zero, end: .zero)) == 2)
        #expect(count(.line(start: .zero, end: .zero)) == 2)
        #expect(count(.box(.zero)) == 4)
        #expect(count(.ellipse(.zero)) == 4)
        #expect(count(.blur(.zero)) == 4)
        #expect(count(.redact(.zero)) == 4)
        #expect(count(.callout(.zero, tail: .zero)) == 5)
        #expect(count(.pen([])) == 0)
        #expect(count(.highlighter([])) == 0)
        #expect(count(.text(.zero)) == 0)
        #expect(count(.step(.zero)) == 0)
    }

    @Test func cornerResizeKeepsOppositeCornerFixed() {
        var annotation = Annotation.test(.box(CGRect(x: 10, y: 10, width: 40, height: 30)))
        annotation.moveHandle(.topLeft, to: CGPoint(x: 0, y: 0))
        guard case .box(let rect) = annotation.shape else { Issue.record("shape changed kind"); return }
        #expect(rect == CGRect(x: 0, y: 0, width: 50, height: 40))
    }

    @Test func cornerResizeNormalizesWhenDraggedPastAnchor() {
        var annotation = Annotation.test(.box(CGRect(x: 10, y: 10, width: 40, height: 30)))
        // Drag the top-left corner past the bottom-right anchor (50, 40).
        annotation.moveHandle(.topLeft, to: CGPoint(x: 60, y: 50))
        guard case .box(let rect) = annotation.shape else { Issue.record("shape changed kind"); return }
        #expect(rect == CGRect(x: 50, y: 40, width: 10, height: 10))
    }

    @Test func arrowEndpointMove() {
        var annotation = Annotation.test(.arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)))
        annotation.moveHandle(.end, to: CGPoint(x: 50, y: 80))
        guard case .arrow(let start, let end) = annotation.shape else { Issue.record("shape changed kind"); return }
        #expect(start == .zero)
        #expect(end == CGPoint(x: 50, y: 80))
    }

    @Test func calloutTailMoveLeavesBubbleAlone() {
        let bubble = CGRect(x: 10, y: 10, width: 100, height: 40)
        var annotation = Annotation.test(.callout(bubble, tail: CGPoint(x: 50, y: 100)))
        annotation.moveHandle(.tail, to: CGPoint(x: 200, y: 30))
        guard case .callout(let rect, let tail) = annotation.shape else { Issue.record("shape changed kind"); return }
        #expect(rect == bubble)
        #expect(tail == CGPoint(x: 200, y: 30))
    }

    // MARK: Misc

    @Test func isTextual() {
        #expect(Annotation.test(.text(.zero)).isTextual)
        #expect(Annotation.test(.callout(.zero, tail: .zero)).isTextual)
        #expect(!Annotation.test(.box(.zero)).isTextual)
        #expect(!Annotation.test(.step(.zero)).isTextual)
    }

    @Test func textEditingOrigin() {
        let textOrigin = CGPoint(x: 33, y: 44)
        #expect(Annotation.test(.text(textOrigin)).textEditingOrigin == textOrigin)
        let bubble = CGRect(x: 5, y: 6, width: 10, height: 10)
        #expect(Annotation.test(.callout(bubble, tail: .zero)).textEditingOrigin == bubble.origin)
    }

    // MARK: Tool metadata (ribbon)

    @Test func everyToolHasLabelAndHelp() {
        for tool in Tool.allCases {
            #expect(!tool.label.isEmpty)
            #expect(!tool.help.isEmpty)
        }
    }

    @Test func toolLabelsAreUnique() {
        let labels = Tool.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
    }

    @Test func everyToolSymbolResolves() {
        for tool in Tool.allCases {
            #expect(
                NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil) != nil,
                "missing SF Symbol \(tool.symbol)"
            )
        }
    }
}
