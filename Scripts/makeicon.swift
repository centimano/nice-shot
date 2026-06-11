// Generates Packaging/AppIcon.icns: a rounded gradient tile with a white
// camera-viewfinder glyph. Run from the repo root:
//   swift Scripts/makeicon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS-style rounded-rect tile with margin.
let margin = size * 0.1
let tile = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
let path = NSBezierPath(roundedRect: tile, xRadius: size * 0.165, yRadius: size * 0.165)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.32, green: 0.42, blue: 0.98, alpha: 1),
    ending: NSColor(calibratedRed: 0.62, green: 0.24, blue: 0.94, alpha: 1)
)
gradient?.draw(in: path, angle: -60)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
if let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let rect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: rect)
    rect.fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(
        x: (size - symbol.size.width) / 2,
        y: (size - symbol.size.height) / 2,
        width: symbol.size.width,
        height: symbol.size.height
    ))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}

let fm = FileManager.default
let iconset = "Packaging/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let master = "\(iconset)/icon_512x512@2x.png"
try! png.write(to: URL(fileURLWithPath: master))

func run(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
}

for px in [16, 32, 64, 128, 256, 512] {
    run(["sips", "-z", "\(px)", "\(px)", master, "--out", "\(iconset)/icon_\(px)x\(px).png"])
    if px < 512 {
        run(["sips", "-z", "\(px * 2)", "\(px * 2)", master, "--out", "\(iconset)/icon_\(px)x\(px)@2x.png"])
    }
}
run(["iconutil", "-c", "icns", iconset, "-o", "Packaging/AppIcon.icns"])
try? fm.removeItem(atPath: iconset)
print("Wrote Packaging/AppIcon.icns")
