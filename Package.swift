// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SuperDuperScreenshot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SuperDuperScreenshot",
            path: "Sources"
        )
    ]
)
