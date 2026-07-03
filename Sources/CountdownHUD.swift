import AppKit
import SwiftUI

/// A small floating countdown shown before a timed capture. Hides itself just
/// before firing so it never appears in the screenshot.
@MainActor
final class CountdownHUD {
    private let panel: NSPanel
    private let hosting: NSHostingView<CountdownView>
    private var timer: Timer?
    private var remaining: Int
    private let onFire: () -> Void

    init(seconds: Int, on screen: NSScreen, onFire: @escaping () -> Void) {
        self.remaining = seconds
        self.onFire = onFire

        hosting = NSHostingView(rootView: CountdownView(remaining: seconds))
        let size = CGSize(width: 120, height: 120)
        let frame = CGRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.orderFrontRegardless()

        // .common keeps the countdown ticking while a menu is open or a
        // window is being dragged into position (event-tracking run-loop
        // modes), which is exactly when timed captures get used.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            timer?.invalidate()
            timer = nil
            panel.orderOut(nil)
            // Let the HUD vanish from screen before the capture happens.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [onFire] in
                onFire()
            }
        } else {
            hosting.rootView = CountdownView(remaining: remaining)
        }
    }
}

private struct CountdownView: View {
    let remaining: Int

    var body: some View {
        Text("\(remaining)")
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 110, height: 110)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
