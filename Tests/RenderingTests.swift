import Testing
import SwiftUI
@testable import NiceShot

private let runningOnCI = ProcessInfo.processInfo.environment["CI"] != nil

/// Reads pixels out of a rendered CGImage. Coordinates are top-left origin,
/// matching annotation space.
private struct PixelReader {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = ctx.data else { return nil }
        let ptr = raw.assumingMemoryBound(to: UInt8.self)
        data = Array(UnsafeBufferPointer(start: ptr, count: width * height * 4))
    }

    func rgba(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    func isWhite(_ x: Int, _ y: Int) -> Bool {
        let p = rgba(x, y)
        return p.r > 240 && p.g > 240 && p.b > 240 && p.a > 200
    }

    func isReddish(_ x: Int, _ y: Int) -> Bool {
        let p = rgba(x, y)
        return p.r > 180 && p.g < 90 && p.b < 90
    }

    func countNonWhite(in rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) where y >= 0 && y < height {
            for x in Int(rect.minX)..<Int(rect.maxX) where x >= 0 && x < width {
                if !isWhite(x, y) { count += 1 }
            }
        }
        return count
    }

    func countDiffering(from other: PixelReader, in rect: CGRect, tolerance: Int = 12) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let a = rgba(x, y)
                let b = other.rgba(x, y)
                if abs(Int(a.r) - Int(b.r)) > tolerance
                    || abs(Int(a.g) - Int(b.g)) > tolerance
                    || abs(Int(a.b) - Int(b.b)) > tolerance {
                    count += 1
                }
            }
        }
        return count
    }
}

private func makeSolidWhiteImage(width: Int = 100, height: Int = 100) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

private func makeCheckerboardImage(width: Int = 100, height: Int = 100, square: Int = 5) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    for y in stride(from: 0, to: height, by: square) {
        for x in stride(from: 0, to: width, by: square) {
            let dark = ((x / square) + (y / square)) % 2 == 0
            ctx.setFillColor(dark
                ? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            // CGContext is bottom-left origin; squares are symmetric so the
            // flip doesn't matter for the pattern.
            ctx.fill(CGRect(x: x, y: y, width: square, height: square))
        }
    }
    return ctx.makeImage()!
}

private let red = Color(red: 1, green: 0, blue: 0)

/// Renders annotations onto a base image through the real export pipeline.
@MainActor
private func render(
    _ annotations: [Annotation],
    on base: CGImage? = nil,
    configure: ((EditorDocument) -> Void)? = nil
) -> PixelReader? {
    let doc = EditorDocument(capture: Capture(image: base ?? makeSolidWhiteImage(), scale: 1, sourceScreen: nil))
    doc.annotations = annotations
    configure?(doc)
    guard let out = doc.renderFinal() else { return nil }
    return PixelReader(out)
}

// MARK: - Tests

@MainActor
@Suite(.disabled(if: runningOnCI, "ImageRenderer needs a GUI session"))
struct RenderingTests {
    @Test func arrowDrawsAlongShaft() throws {
        let reader = try #require(render([
            .test(.arrow(start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50)), color: red, strokeWidth: 6)
        ]))
        #expect(reader.isReddish(50, 50), "shaft pixel should be red")
        #expect(reader.isWhite(50, 20), "far from the arrow stays untouched")
    }

    @Test func boxStrokesEdgesNotCenter() throws {
        let reader = try #require(render([
            .test(.box(CGRect(x: 20, y: 20, width: 60, height: 60)), color: red, strokeWidth: 6)
        ]))
        #expect(reader.isReddish(50, 20), "top edge stroked")
        #expect(reader.isWhite(50, 50), "interior stays unfilled")
    }

    @Test func ellipseStrokesEdgeNotCenter() throws {
        let reader = try #require(render([
            .test(.ellipse(CGRect(x: 20, y: 20, width: 60, height: 60)), color: red, strokeWidth: 6)
        ]))
        #expect(reader.isReddish(50, 20), "top of the ellipse stroked")
        #expect(reader.isWhite(50, 50), "interior stays unfilled")
    }

    @Test func penDrawsAlongPath() throws {
        let reader = try #require(render([
            .test(.pen([CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 30)]), color: red, strokeWidth: 6)
        ]))
        #expect(reader.isReddish(50, 30))
        #expect(reader.isWhite(50, 70))
    }

    @Test func highlighterIsTranslucent() throws {
        let yellow = Color(red: 1, green: 1, blue: 0)
        let reader = try #require(render([
            .test(.highlighter([CGPoint(x: 20, y: 50), CGPoint(x: 80, y: 50)]), color: yellow, strokeWidth: 6)
        ]))
        let p = reader.rgba(50, 50)
        #expect(p.r > 220 && p.g > 200, "highlight keeps the page bright")
        #expect(p.b < 210, "but visibly tints it yellow")
        #expect(reader.isWhite(50, 10))
    }

    @Test func textDrawsGlyphs() throws {
        let reader = try #require(render([
            .test(.text(CGPoint(x: 10, y: 20)), color: red, fontSize: 36, text: "AAAA")
        ]))
        #expect(reader.countNonWhite(in: CGRect(x: 5, y: 15, width: 90, height: 60)) > 30,
                "glyphs should leave a visible footprint")
    }

    @Test func calloutFillsBubble() throws {
        let reader = try #require(render([
            .test(.callout(CGRect(x: 20, y: 20, width: 60, height: 40), tail: CGPoint(x: 30, y: 90)), color: red)
        ]))
        #expect(reader.isReddish(50, 40), "bubble interior is filled")
        #expect(reader.isWhite(90, 90), "outside the callout stays clean")
    }

    @Test func stepBadgeDrawsFilledCircle() throws {
        let reader = try #require(render([
            .test(.step(CGPoint(x: 50, y: 50)), color: red, fontSize: 22, number: 3)
        ]))
        #expect(reader.isReddish(40, 50), "inside the badge, left of the numeral")
        #expect(reader.isWhite(50, 10), "outside the badge")
    }

    @Test func redactIsOpaqueBlack() throws {
        let reader = try #require(render([
            .test(.redact(CGRect(x: 30, y: 30, width: 40, height: 40)))
        ]))
        let p = reader.rgba(50, 50)
        #expect(p.r < 25 && p.g < 25 && p.b < 25, "redaction must be black")
        #expect(p.a > 240, "and fully opaque")
    }

    @Test func blurObscuresOnlyItsRegion() throws {
        let base = makeCheckerboardImage()
        let withBlur = try #require(render([
            .test(.blur(CGRect(x: 20, y: 20, width: 40, height: 40)))
        ], on: base))
        let without = try #require(render([], on: base))

        let changedInside = withBlur.countDiffering(from: without, in: CGRect(x: 22, y: 22, width: 36, height: 36))
        #expect(changedInside > 50, "pixelation must visibly change the detailed region")
        let changedOutside = withBlur.countDiffering(from: without, in: CGRect(x: 70, y: 70, width: 25, height: 25))
        #expect(changedOutside == 0, "pixels outside the blur rect must be untouched")
    }

    @Test func borderEffectDrawsEdges() throws {
        let reader = try #require(render([]) { doc in
            doc.borderOn = true
            doc.borderColor = Color(red: 0, green: 0, blue: 0)
            doc.borderWidth = 4
        })
        let edge = reader.rgba(50, 1)
        #expect(edge.r < 90 && edge.g < 90 && edge.b < 90, "border darkens the top edge")
        #expect(reader.isWhite(50, 50), "interior untouched")
    }

    @Test func cornerRadiusClipsCorners() throws {
        let reader = try #require(render([]) { doc in
            doc.cornerRadius = 20
        })
        #expect(reader.rgba(1, 1).a < 60, "corner pixel clipped to transparent")
        #expect(reader.rgba(50, 50).a > 240, "center stays opaque")
    }
}
