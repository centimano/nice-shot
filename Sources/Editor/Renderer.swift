import SwiftUI

/// Draws annotations into a `GraphicsContext`. The same code path renders the
/// live editor canvas and the flattened export, guaranteeing WYSIWYG output.
enum Renderer {
    static func draw(
        _ annotation: Annotation,
        in context: inout GraphicsContext,
        unit: CGFloat,
        imageSize: CGSize,
        pixelated: CGImage?,
        selected: Bool
    ) {
        let lineWidth = annotation.strokeWidth * unit

        switch annotation.shape {
        case .arrow(let start, let end):
            drawArrow(from: start, to: end, color: annotation.color, lineWidth: lineWidth, in: &context)

        case .line(let start, let end):
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .box(let rect):
            context.stroke(
                Path(roundedRect: rect, cornerRadius: lineWidth / 2),
                with: .color(annotation.color),
                style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round)
            )

        case .ellipse(let rect):
            context.stroke(Path(ellipseIn: rect), with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth))

        case .pen(let points):
            guard points.count > 1 else { break }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        case .highlighter(let points):
            guard points.count > 1 else { break }
            var path = Path()
            path.addLines(points)
            var layer = context
            layer.blendMode = .multiply
            layer.stroke(path, with: .color(annotation.color.opacity(0.45)),
                         style: StrokeStyle(lineWidth: lineWidth * 4, lineCap: .round, lineJoin: .round))

        case .text(let origin):
            guard !annotation.text.isEmpty else { break }
            let styled = Text(annotation.text)
                .font(.system(size: annotation.fontSize * unit, weight: .semibold))
                .foregroundColor(annotation.color)
            // Soft white halo for legibility on busy backgrounds.
            var halo = context
            halo.addFilter(.shadow(color: .white.opacity(0.9), radius: 1.5 * unit))
            halo.draw(styled, at: origin, anchor: .topLeading)

        case .callout(let rect, let tail):
            drawCallout(rect: rect, tail: tail, annotation: annotation, unit: unit, in: &context)

        case .step(let center):
            let radius = Annotation.stepRadius(fontSize: annotation.fontSize, unit: unit)
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 2 * unit, y: unit))
            shadowed.fill(Path(ellipseIn: circle), with: .color(annotation.color))
            context.stroke(Path(ellipseIn: circle), with: .color(.white),
                           style: StrokeStyle(lineWidth: max(1.5, 1.5 * unit)))
            context.draw(
                Text("\(annotation.number)")
                    .font(.system(size: radius * 1.05, weight: .bold, design: .rounded))
                    .foregroundColor(.white),
                at: center, anchor: .center
            )

        case .blur(let rect):
            if let pixelated {
                var layer = context
                layer.clip(to: Path(rect))
                layer.draw(
                    Image(decorative: pixelated, scale: 1),
                    in: CGRect(origin: .zero, size: imageSize)
                )
            } else {
                context.fill(Path(rect), with: .color(.gray.opacity(0.8)))
            }

        case .redact(let rect):
            context.fill(Path(roundedRect: rect, cornerRadius: 2 * unit), with: .color(.black))
        }

        if selected {
            let outline = annotation.bounds(unit: unit).insetBy(dx: -5 * unit, dy: -5 * unit)
            context.stroke(
                Path(roundedRect: outline, cornerRadius: 3 * unit),
                with: .color(.blue),
                style: StrokeStyle(lineWidth: max(1.5, 1.2 * unit), dash: [6 * unit, 4 * unit])
            )
            for (_, position) in annotation.handlePositions(unit: unit) {
                let r = CGRect(
                    x: position.x - 4.5 * unit,
                    y: position.y - 4.5 * unit,
                    width: 9 * unit,
                    height: 9 * unit
                )
                context.fill(Path(ellipseIn: r), with: .color(.white))
                context.stroke(Path(ellipseIn: r), with: .color(.blue),
                               style: StrokeStyle(lineWidth: max(1, unit)))
            }
        }
    }

    // MARK: - Arrow

    private static func drawArrow(
        from start: CGPoint, to end: CGPoint,
        color: Color, lineWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let angle = atan2(dy, dx)
        let headLength = min(max(12, lineWidth * 3.5), length * 0.6)

        // Shaft stops short of the tip so the head stays crisp.
        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * headLength * 0.7,
            y: end.y - sin(angle) * headLength * 0.7
        )
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: shaftEnd)
        context.stroke(shaft, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        let spread: CGFloat = .pi / 7
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(
            x: end.x - cos(angle - spread) * headLength,
            y: end.y - sin(angle - spread) * headLength
        ))
        head.addLine(to: CGPoint(
            x: end.x - cos(angle + spread) * headLength,
            y: end.y - sin(angle + spread) * headLength
        ))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    // MARK: - Callout

    private static func drawCallout(
        rect: CGRect, tail: CGPoint,
        annotation: Annotation, unit: CGFloat,
        in context: inout GraphicsContext
    ) {
        let corner = min(10 * unit, rect.height / 3)
        var path = Path(roundedRect: rect, cornerRadius: corner)
        path.addPath(tailPath(bubble: rect, tail: tail, unit: unit))

        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: 3 * unit, y: unit))
        shadowed.fill(path, with: .color(annotation.color))

        if !annotation.text.isEmpty {
            context.draw(
                Text(annotation.text)
                    .font(.system(size: annotation.fontSize * unit, weight: .semibold))
                    .foregroundColor(.white),
                in: rect.insetBy(dx: 10 * unit, dy: 6 * unit)
            )
        }
    }

    private static func tailPath(bubble: CGRect, tail: CGPoint, unit: CGFloat) -> Path {
        let baseHalf = min(10 * unit, bubble.width / 4, bubble.height / 4)
        var a: CGPoint
        var b: CGPoint

        if tail.y >= bubble.maxY { // below
            let x = tail.x.clamped(bubble.minX + baseHalf * 2, bubble.maxX - baseHalf * 2)
            a = CGPoint(x: x - baseHalf, y: bubble.maxY - 1)
            b = CGPoint(x: x + baseHalf, y: bubble.maxY - 1)
        } else if tail.y <= bubble.minY { // above
            let x = tail.x.clamped(bubble.minX + baseHalf * 2, bubble.maxX - baseHalf * 2)
            a = CGPoint(x: x - baseHalf, y: bubble.minY + 1)
            b = CGPoint(x: x + baseHalf, y: bubble.minY + 1)
        } else if tail.x <= bubble.minX { // left
            let y = tail.y.clamped(bubble.minY + baseHalf * 2, bubble.maxY - baseHalf * 2)
            a = CGPoint(x: bubble.minX + 1, y: y - baseHalf)
            b = CGPoint(x: bubble.minX + 1, y: y + baseHalf)
        } else { // right
            let y = tail.y.clamped(bubble.minY + baseHalf * 2, bubble.maxY - baseHalf * 2)
            a = CGPoint(x: bubble.maxX - 1, y: y - baseHalf)
            b = CGPoint(x: bubble.maxX - 1, y: y + baseHalf)
        }

        var path = Path()
        path.move(to: a)
        path.addLine(to: tail)
        path.addLine(to: b)
        path.closeSubpath()
        return path
    }
}

extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        upper < lower ? self : Swift.min(Swift.max(self, lower), upper)
    }
}
