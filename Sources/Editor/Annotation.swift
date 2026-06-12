import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case select, crop, arrow, line, box, ellipse, pen, highlighter, text, callout, step, blur, redact

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .box: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "pencil.line"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .callout: return "text.bubble"
        case .step: return "number.circle"
        case .blur: return "squareshape.split.3x3"
        case .redact: return "eye.slash"
        }
    }

    /// Short caption shown under the icon in the tool ribbon.
    var label: String {
        switch self {
        case .select: return "Select"
        case .crop: return "Crop"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .box: return "Box"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen"
        case .highlighter: return "Marker"
        case .text: return "Text"
        case .callout: return "Callout"
        case .step: return "Step"
        case .blur: return "Blur"
        case .redact: return "Redact"
        }
    }

    var help: String {
        switch self {
        case .select: return "Select & Move"
        case .crop: return "Crop"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .box: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .callout: return "Callout"
        case .step: return "Step Number"
        case .blur: return "Blur (Pixelate)"
        case .redact: return "Redact"
        }
    }
}

/// One markup element. All geometry is stored in image-pixel coordinates so
/// the on-screen canvas and the flattened export render identically.
struct Annotation: Identifiable {
    enum Shape {
        case arrow(start: CGPoint, end: CGPoint)
        case line(start: CGPoint, end: CGPoint)
        case box(CGRect)
        case ellipse(CGRect)
        case pen([CGPoint])
        case highlighter([CGPoint])
        case text(CGPoint)
        case callout(CGRect, tail: CGPoint)
        case step(CGPoint)
        case blur(CGRect)
        case redact(CGRect)
    }

    let id = UUID()
    var shape: Shape
    var color: Color
    var strokeWidth: CGFloat
    var fontSize: CGFloat
    var text: String = ""
    var number: Int = 0

    var isTextual: Bool {
        switch shape {
        case .text, .callout: return true
        default: return false
        }
    }

    /// Rough bounding box (pixel coords) used for hit-testing and the
    /// selection outline.
    func bounds(unit: CGFloat) -> CGRect {
        switch shape {
        case .arrow(let a, let b), .line(let a, let b):
            return CGRect(points: a, b).insetBy(dx: -strokeWidth * unit, dy: -strokeWidth * unit)
        case .box(let r), .ellipse(let r), .blur(let r), .redact(let r):
            return r
        case .pen(let pts), .highlighter(let pts):
            guard let first = pts.first else { return .zero }
            var rect = CGRect(origin: first, size: .zero)
            for p in pts.dropFirst() {
                rect = rect.union(CGRect(origin: p, size: .zero))
            }
            return rect.insetBy(dx: -strokeWidth * unit * 2, dy: -strokeWidth * unit * 2)
        case .text(let origin):
            let lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
            let longest = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(\.count).max() ?? 1
            let size = CGSize(
                width: max(40, CGFloat(longest) * fontSize * unit * 0.62),
                height: CGFloat(lines) * fontSize * unit * 1.3
            )
            return CGRect(origin: origin, size: size)
        case .callout(let r, let tail):
            return r.union(CGRect(origin: tail, size: .zero))
        case .step(let center):
            let radius = Annotation.stepRadius(fontSize: fontSize, unit: unit)
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    static func stepRadius(fontSize: CGFloat, unit: CGFloat) -> CGFloat {
        max(14, fontSize * 0.85) * unit
    }

    func hitTest(_ point: CGPoint, unit: CGFloat) -> Bool {
        bounds(unit: unit).insetBy(dx: -8 * unit, dy: -8 * unit).contains(point)
    }

    // MARK: - Resize handles

    enum Handle: Hashable {
        case start, end
        case topLeft, topRight, bottomLeft, bottomRight
        case tail
    }

    /// Grab points shown when the annotation is selected, in pixel coords.
    func handlePositions(unit: CGFloat) -> [(Handle, CGPoint)] {
        func corners(_ r: CGRect) -> [(Handle, CGPoint)] {
            [
                (.topLeft, CGPoint(x: r.minX, y: r.minY)),
                (.topRight, CGPoint(x: r.maxX, y: r.minY)),
                (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
                (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
            ]
        }
        switch shape {
        case .arrow(let a, let b), .line(let a, let b):
            return [(.start, a), (.end, b)]
        case .box(let r), .ellipse(let r), .blur(let r), .redact(let r):
            return corners(r)
        case .callout(let r, let tail):
            return corners(r) + [(.tail, tail)]
        case .pen, .highlighter, .text, .step:
            return []
        }
    }

    mutating func moveHandle(_ handle: Handle, to point: CGPoint) {
        func resized(_ r: CGRect) -> CGRect {
            let anchor: CGPoint
            switch handle {
            case .topLeft: anchor = CGPoint(x: r.maxX, y: r.maxY)
            case .topRight: anchor = CGPoint(x: r.minX, y: r.maxY)
            case .bottomLeft: anchor = CGPoint(x: r.maxX, y: r.minY)
            default: anchor = CGPoint(x: r.minX, y: r.minY)
            }
            return CGRect(points: anchor, point)
        }
        switch shape {
        case .arrow(let a, let b):
            shape = .arrow(start: handle == .start ? point : a, end: handle == .end ? point : b)
        case .line(let a, let b):
            shape = .line(start: handle == .start ? point : a, end: handle == .end ? point : b)
        case .box(let r): shape = .box(resized(r))
        case .ellipse(let r): shape = .ellipse(resized(r))
        case .blur(let r): shape = .blur(resized(r))
        case .redact(let r): shape = .redact(resized(r))
        case .callout(let r, let tail):
            if handle == .tail {
                shape = .callout(r, tail: point)
            } else {
                shape = .callout(resized(r), tail: tail)
            }
        case .pen, .highlighter, .text, .step:
            break
        }
    }

    mutating func translate(by delta: CGSize) {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.width, y: p.y + delta.height) }
        func move(_ r: CGRect) -> CGRect { r.offsetBy(dx: delta.width, dy: delta.height) }

        switch shape {
        case .arrow(let a, let b): shape = .arrow(start: move(a), end: move(b))
        case .line(let a, let b): shape = .line(start: move(a), end: move(b))
        case .box(let r): shape = .box(move(r))
        case .ellipse(let r): shape = .ellipse(move(r))
        case .pen(let pts): shape = .pen(pts.map(move))
        case .highlighter(let pts): shape = .highlighter(pts.map(move))
        case .text(let p): shape = .text(move(p))
        case .callout(let r, let tail): shape = .callout(move(r), tail: move(tail))
        case .step(let p): shape = .step(move(p))
        case .blur(let r): shape = .blur(move(r))
        case .redact(let r): shape = .redact(move(r))
        }
    }

    /// Where the inline text editor should sit, in pixel coords.
    var textEditingOrigin: CGPoint {
        switch shape {
        case .text(let origin): return origin
        case .callout(let rect, _): return rect.origin
        default: return .zero
        }
    }
}

extension CGRect {
    init(points a: CGPoint, _ b: CGPoint) {
        self.init(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}
