import AppKit
import SwiftUI

/// The floating panel that appears after a single capture: thumbnail plus
/// Edit / Save / Copy / dismiss. Non-activating so it never steals focus.
/// A second capture while it's showing moves both into a `CaptureTray`.
@MainActor
final class PostCapturePanel {
    var onEdit: (() -> Void)?
    /// Called when the capture has been dealt with (saved, copied, or
    /// discarded) — including a save that finishes after the capture was
    /// already handed over to the tray.
    var onDismiss: (() -> Void)?

    /// Identity shared with the tray item this capture becomes if the panel
    /// is folded into a tray.
    let id = UUID()
    let capture: Capture
    let autoCopied: Bool
    private var panel: NSPanel!

    init(capture: Capture, autoCopied: Bool = false) {
        self.capture = capture
        self.autoCopied = autoCopied

        let view = PostCaptureView(
            thumbnail: Thumbnail.make(from: capture.image, maxPoints: CGSize(width: 300, height: 190)),
            sizeLabel: "\(capture.image.width) × \(capture.image.height) px",
            saveLabel: AppSettings.shared.askWhereToSave ? "Save…" : "Save",
            autoCopied: autoCopied,
            shareImage: { capture.image },
            shareScale: capture.scale,
            onEdit: { [weak self] in self?.onEdit?() },
            onSave: { [weak self] in self?.save() },
            onCopy: { [weak self] in self?.copy() },
            onClose: { [weak self] in self?.onDismiss?() }
        )

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting

        let screen = capture.sourceScreen ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            panel.setFrameOrigin(FloatingPanelPlacement.origin(windowSize: size, visibleFrame: vf))
        }
    }

    private func save() {
        if Exporter.save(image: capture.image, scale: capture.scale) {
            onDismiss?()
        }
        // A cancelled save dialog keeps the capture around.
    }

    private func copy() {
        Exporter.copyToClipboard(image: capture.image, scale: capture.scale)
        onDismiss?()
    }

    func show() {
        panel.orderFrontRegardless()
        CaptureExclusions.add(panel)
    }

    func close() {
        CaptureExclusions.remove(panel)
        panel.orderOut(nil)
        panel.close()
    }
}

/// Where the capture panel and tray sit: the bottom-right corner of the
/// screen's usable area. Both share it so the tray replaces the panel in
/// place.
enum FloatingPanelPlacement {
    static let margin: CGFloat = 16

    static func origin(windowSize: CGSize, visibleFrame vf: CGRect) -> CGPoint {
        CGPoint(x: vf.maxX - windowSize.width - margin, y: vf.minY + margin)
    }
}

private struct PostCaptureView: View {
    let thumbnail: NSImage
    let sizeLabel: String
    let saveLabel: String
    let autoCopied: Bool
    let shareImage: () -> CGImage?
    let shareScale: CGFloat
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.separator, lineWidth: 1)
                    )

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Discard")
            }

            HStack(spacing: 6) {
                Text(sizeLabel)
                if autoCopied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Copied to the clipboard automatically")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Label("Edit…", systemImage: "pencil.tip.crop.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(saveLabel, action: onSave)
                    .controlSize(.large)

                Button("Copy", action: onCopy)
                    .controlSize(.large)

                ShareButton(image: shareImage, scale: shareScale, labeled: false)
                    .controlSize(.large)
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .padding(20)
    }
}
