import AppKit
import UniformTypeIdentifiers

@MainActor
enum Exporter {
    static func defaultFileName(date: Date = Date(), counter: Int = 0) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = fmt.string(from: date)
        return counter > 0 ? "Screenshot \(stamp) \(counter + 1).png" : "Screenshot \(stamp).png"
    }

    /// First path in `folder` based on the default name that doesn't collide
    /// with an existing file ("… 2.png", "… 3.png", …).
    static func uniqueDestination(in folder: URL, date: Date = Date()) -> URL {
        var url = folder.appendingPathComponent(defaultFileName(date: date))
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(defaultFileName(date: date, counter: counter))
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = AppSettings.shared.saveFolder
        panel.nameFieldStringValue = defaultFileName()
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(image: image, scale: scale, to: url)
    }

    @discardableResult
    static func quickSave(image: CGImage, scale: CGFloat) -> Bool {
        let folder = AppSettings.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return write(image: image, scale: scale, to: uniqueDestination(in: folder))
    }

    private static func write(image: CGImage, scale: CGFloat, to url: URL) -> Bool {
        guard let data = pngData(from: image, scale: scale) else { return false }
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
