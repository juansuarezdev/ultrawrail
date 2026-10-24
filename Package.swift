// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Linkr",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LayoutEngine"),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine"]),
    ]
)
