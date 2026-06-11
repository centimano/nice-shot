import AppKit
import ScreenCaptureKit

/// The result of any capture: full-resolution pixels plus the backing scale
/// they were captured at (2.0 on HiDPI displays), so the editor can size
/// strokes and fonts in screen points.
struct Capture {
    let image: CGImage
    let scale: CGFloat
    let sourceScreen: NSScreen?

    var pointSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Could not find the display to capture."
        case .cropFailed: return "Could not crop the captured image."
        }
    }
}

enum CaptureEngine {
    /// Capture a whole display, optionally cropped to `rect` — a rectangle in
    /// screen points with a top-left origin relative to that screen.
    static func captureDisplay(screen: NSScreen, cropTo rect: CGRect?, showsCursor: Bool = false) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let scale = screen.backingScaleFactor
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = showsCursor
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        guard let rect else { return image }
        guard let cropped = image.cropping(to: pixelRect(for: rect, scale: scale)) else {
            throw CaptureError.cropFailed
        }
        return cropped
    }

    /// Convert a selection in screen points (top-left origin) into the integral
    /// pixel rect to crop from the captured image.
    static func pixelRect(for rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (rect.minX * scale).rounded(.down),
            y: (rect.minY * scale).rounded(.down),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
    }

    /// Capture a single window cleanly (no overlapping content).
    static func captureWindow(_ window: SCWindow, showsCursor: Bool = false) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = showsCursor
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
