import Foundation
import os

/// Unified-logging channels (view them in Console.app by filtering on the
/// app's bundle identifier). `Logger` replaces NSLog: it is cheaper, keeps
/// interpolated values private by default, and never treats a message as a
/// format string.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jeff.nice-shot"

    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}
