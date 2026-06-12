// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NiceShot",
    platforms: [.macOS(.v14)],
    targets: [
        // All app code lives in this library so the test target can link it.
        .target(
            name: "NiceShot",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Thin executable: just the @main entry point.
        .executableTarget(
            name: "NiceShotApp",
            dependencies: ["NiceShot"],
            path: "App",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Tests are an executable (`swift run NiceShotTests`), not
        // a .testTarget: the Command Line Tools' test helper silently runs
        // nothing, so Tests/TestMain.swift invokes Swift Testing directly.
        // The extra search paths locate Testing.framework when only the
        // Command Line Tools are installed; harmless with full Xcode.
        .executableTarget(
            name: "NiceShotTests",
            dependencies: ["NiceShot"],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        ),
    ]
)
