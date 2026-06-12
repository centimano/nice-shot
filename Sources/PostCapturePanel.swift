import AppKit
import SwiftUI

/// The floating panel that appears after every capture: thumbnail plus
/// Edit / Save / Copy / dismiss. Non-activating so it never steals focus.
@MainActor
final class PostCapturePanel {
    var onEdit: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let capture: Capture
    private var panel: NSPanel!

    init(capture: Capture, stackIndex: Int = 0, autoCopied: Bool = false) {
        self.capture = capture

        let view = PostCaptureView(
            thumbnail: NSImage(cgImage: capture.image, size: capture.pointSize),
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
            // Stack additional captures upward so they don't cover each other.
            let yOffset = CGFloat(min(stackIndex, 6)) * 36
            panel.setFrameOrigin(CGPoint(x: vf.maxX - size.width - 16, y: vf.minY + 16 + yOffset))
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
    }

    func close() {
        panel.orderOut(nil)
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
