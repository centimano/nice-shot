import AppKit

/// Plays the system screenshot shutter sound after a capture, honoring the
/// "Play shutter sound" setting.
@MainActor
enum CaptureSound {
    /// macOS ships its screenshot sound outside /System/Library/Sounds; fall
    /// back to a regular named sound if a future release moves it.
    private static let systemSoundPaths = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif",
    ]

    private static let sound: NSSound? = {
        for path in systemSoundPaths where FileManager.default.fileExists(atPath: path) {
            if let sound = NSSound(contentsOfFile: path, byReference: true) {
                return sound
            }
        }
        return NSSound(named: "Pop")
    }()

    static func play() {
        guard AppSettings.shared.playCaptureSound else { return }
        sound?.stop()
        sound?.play()
    }
}
