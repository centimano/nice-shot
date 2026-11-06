import AppKit
import SwiftUI

/// A toolbar/panel button that opens the macOS share sheet for an image.
/// The image is produced lazily on click (the editor flattens annotations at
/// that moment) and shared as a PNG file so receivers get a proper filename.
struct ShareButton: View {
    /// Returns the image to share, or nil to abort (e.g. render failure).
    let image: () -> CGImage?
    let scale: CGFloat
    var labeled = true

    @State private var anchor: NSView?

    var body: some View {
        Button {
            share()
        } label: {
            if labeled {
                Label("Share", systemImage: "square.and.arrow.up")
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .background(AnchorReader { anchor = $0 })
        .help("Share")
    }

    private func share() {
        guard let anchor,
              let image = image(),
              let png = Exporter.pngData(from: image, scale: scale),
              let url = ShareFiles.write(png, named: Exporter.defaultFileName()) else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }
}

/// Staging area for files handed to the share sheet. Screenshots can hold
/// sensitive content, so they live in a private (owner-only) folder inside
/// the per-user temporary directory and are cleaned up instead of piling up:
/// everything is removed at launch, and files older than an hour are removed
/// whenever something new is shared. (Recent files are kept because a share
/// service such as AirDrop may still be reading them.)
@MainActor
enum ShareFiles {
    static let maxAge: TimeInterval = 60 * 60

    static var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NiceShot-Share", isDirectory: true)
    }

    /// Write `data` as `name` in a fresh per-share subfolder (so two shares
    /// in the same second never collide). Returns nil if the write failed.
    static func write(_ data: Data, named name: String, in root: URL = directory) -> URL? {
        purge(olderThan: maxAge, in: root)
        let fm = FileManager.default
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fm.createDirectory(
                at: folder,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .withoutOverwriting)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        } catch {
            Log.export.error("Could not stage file for sharing: \(error.localizedDescription)")
            return nil
        }
    }

    /// Remove staged shares last modified more than `age` seconds ago; pass
    /// 0 to remove everything.
    static func purge(olderThan age: TimeInterval = 0, now: Date = Date(), in root: URL = directory) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if age <= 0 || now.timeIntervalSince(modified) >= age {
                try? fm.removeItem(at: entry)
            }
        }
    }
}

/// Invisible helper that hands the underlying NSView to SwiftUI, so the share
/// popover can anchor to the button's real position.
private struct AnchorReader: NSViewRepresentable {
    let onReady: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onReady(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
