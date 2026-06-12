import AppKit
import SwiftUI
@testable import NiceShot

/// A solid-color in-memory image standing in for a real screen capture.
func makeTestImage(width: Int = 200, height: Int = 100) -> CGImage {
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

func makeTestCapture(width: Int = 200, height: Int = 100, scale: CGFloat = 1) -> Capture {
    Capture(image: makeTestImage(width: width, height: height), scale: scale, sourceScreen: nil)
}

extension Annotation {
    static func test(
        _ shape: Shape,
        color: Color = .red,
        strokeWidth: CGFloat = 4,
        fontSize: CGFloat = 22,
        text: String = "",
        number: Int = 0
    ) -> Annotation {
        var annotation = Annotation(shape: shape, color: color, strokeWidth: strokeWidth, fontSize: fontSize)
        annotation.text = text
        annotation.number = number
        return annotation
    }
}
