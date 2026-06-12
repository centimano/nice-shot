import AppKit
import UniformTypeIdentifiers

/// Still-image formats the app can save.
enum ImageFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }

    static func from(url: URL) -> ImageFormat {
        ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
    }
}

@MainActor
enum Exporter {
    static func defaultFileName(date: Date = Date(), counter: Int = 0, fileExtension: String = "png") -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = fmt.string(from: date)
        let name = counter > 0 ? "Screenshot \(stamp) \(counter + 1)" : "Screenshot \(stamp)"
        return "\(name).\(fileExtension)"
    }

    /// First path in `folder` based on the default name that doesn't collide
    /// with an existing file ("… 2.png", "… 3.png", …).
    static func uniqueDestination(in folder: URL, date: Date = Date(), fileExtension: String = "png") -> URL {
        var url = folder.appendingPathComponent(defaultFileName(date: date, fileExtension: fileExtension))
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(
                defaultFileName(date: date, counter: counter, fileExtension: fileExtension))
            counter += 1
        }
        return url
    }

    /// PNG data with point-size metadata so HiDPI captures report the right DPI.
    static func pngData(from image: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep.representation(using: .png, properties: [:])
    }

    /// JPEG can't store transparency, so the image is composited onto white
    /// before encoding (window captures carry alpha in their shadow margins).
    static func jpegData(from image: CGImage, scale: CGFloat, quality: Double) -> Data? {
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(bounds)
        ctx.draw(image, in: bounds)
        guard let flattened = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: flattened)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    static func imageData(from image: CGImage, scale: CGFloat, format: ImageFormat, jpegQuality: Double) -> Data? {
        switch format {
        case .png: pngData(from: image, scale: scale)
        case .jpeg: jpegData(from: image, scale: scale, quality: jpegQuality)
        }
    }

    /// Save honoring the user's preference: a save dialog, or quick-save into
    /// the configured folder. Returns false if cancelled or the write failed.
    @discardableResult
    static func save(image: CGImage, scale: CGFloat) -> Bool {
        AppSettings.shared.askWhereToSave
            ? saveWithPanel(image: image, scale: scale)
            : quickSave(image: image, scale: scale)
    }

    @discardableResult
    static func saveWithPanel(image: CGImage, scale: CGFloat) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let format = AppSettings.shared.saveFormat
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .jpeg ? [.jpeg, .png] : [.png, .jpeg]
        if #available(macOS 15, *) {
            // Format pop-up in the dialog; on macOS 14 typing the other
            // extension in the name field switches format instead.
            panel.showsContentTypes = true
        }
        panel.directoryURL = AppSettings.shared.saveFolder
        panel.nameFieldStringValue = defaultFileName(fileExtension: format.fileExtension)
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(image: image, scale: scale, to: url)
    }

    @discardableResult
    static func quickSave(image: CGImage, scale: CGFloat) -> Bool {
        let folder = AppSettings.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let ext = AppSettings.shared.saveFormat.fileExtension
        return write(image: image, scale: scale, to: uniqueDestination(in: folder, fileExtension: ext))
    }

    /// The format is taken from the destination's extension, so a format
    /// chosen in the save dialog wins over the preference it started from.
    private static func write(image: CGImage, scale: CGFloat, to url: URL) -> Bool {
        guard let data = imageData(
            from: image,
            scale: scale,
            format: .from(url: url),
            jpegQuality: AppSettings.shared.jpegQuality
        ) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could Not Save Screenshot"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    static func copyToClipboard(image: CGImage, scale: CGFloat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(
            cgImage: image,
            size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        )
        pasteboard.writeObjects([nsImage])
        if let png = pngData(from: image, scale: scale) {
            pasteboard.setData(png, forType: .png)
        }
    }
}
