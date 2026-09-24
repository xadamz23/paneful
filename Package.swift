// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Paneful",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Paneful", targets: ["Paneful"])],
    targets: [
        .target(name: "PanefulCore"),
        .executableTarget(
            name: "Paneful",
            dependencies: ["PanefulCore"],
            // AppKit callbacks (event monitors, timers) are main-thread but not annotated for Swift 6 isolation.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PanefulCoreTests",
            dependencies: ["PanefulCore"],
            // Without Xcode, SwiftPM intermittently forgets to load Swift Testing's macro plugin.
            swiftSettings: [.unsafeFlags([
                "-load-plugin-library",
                "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib",
            ])]
        ),
    ]
)
