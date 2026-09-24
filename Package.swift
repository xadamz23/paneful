// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Paneful",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PanefulCore"),
        .testTarget(name: "PanefulCoreTests", dependencies: ["PanefulCore"]),
    ]
)
