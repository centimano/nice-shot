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
              let png = Exporter.pngData(from: image, scale: scale) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(Exporter.defaultFileName())
        do {
            try png.write(to: url)
        } catch {
            return
        }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
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
