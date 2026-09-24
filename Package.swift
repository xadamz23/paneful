// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Paneful",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PanefulCore"),
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
