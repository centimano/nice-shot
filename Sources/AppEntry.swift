import AppKit

/// Entry point called by the thin executable target. Everything else in this
/// module is library code so the test suite can link against it.
@MainActor
public func runNiceShot() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
