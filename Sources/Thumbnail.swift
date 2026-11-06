import AppKit

/// Small preview images for the capture panel and tray. Drawing a full
/// 5K capture into a 300-point thumbnail makes the window server keep (and
/// rescale) the whole bitmap for every redraw; a pre-shrunk copy keeps each
/// floating panel to a few hundred kilobytes.
enum Thumbnail {
    /// Largest size, in pixels, that fits `maxPixels` while keeping the
    /// aspect ratio. Never upscales; always at least 1×1.
    static func fittedPixelSize(for size: CGSize, maxPixels: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let ratio = min(1, maxPixels.width / size.width, maxPixels.height / size.height)
        return CGSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded())
        )
    }

    /// Downscaled copy of `image` fitting `maxPoints` at a 2× backing scale
    /// (crisp on Retina), returned as an NSImage sized in points. Falls back
    /// to wrapping the original if the downscale fails.
    static func make(from image: CGImage, maxPoints: CGSize) -> NSImage {
        let thumb = bitmap(from: image, maxPoints: maxPoints)
        return NSImage(cgImage: thumb.image, size: thumb.pointSize)
    }

    /// The pixels behind `make`: the downscaled bitmap and its size in points.
    static func bitmap(from image: CGImage, maxPoints: CGSize) -> (image: CGImage, pointSize: CGSize) {
        let maxPixels = CGSize(width: maxPoints.width * 2, height: maxPoints.height * 2)
        let source = CGSize(width: image.width, height: image.height)
        let target = fittedPixelSize(for: source, maxPixels: maxPixels)
        let pointSize = CGSize(width: target.width / 2, height: target.height / 2)

        guard target != source, let scaled = downscale(image, to: target) else {
            return (image, pointSize)
        }
        return (scaled, pointSize)
    }

    static func downscale(_ image: CGImage, to size: CGSize) -> CGImage? {
        // Prefer the capture's own color space (Display P3 on most Macs) so
        // the preview's colors match; fall back to sRGB for spaces an 8-bit
        // RGB context can't use (grayscale, extended range).
        var spaces: [CGColorSpace] = []
        if let own = image.colorSpace, own.model == .rgb, own.supportsOutput { spaces.append(own) }
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) { spaces.append(srgb) }
        for space in spaces {
            guard let ctx = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            if let scaled = ctx.makeImage() { return scaled }
        }
        return nil
    }
}
