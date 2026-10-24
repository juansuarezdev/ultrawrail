// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Linkr",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LayoutEngine"),
        .target(name: "LinkrCore", dependencies: ["LayoutEngine"]),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine"]),
        .testTarget(
            name: "LinkrCoreTests",
            dependencies: ["LinkrCore", "LayoutEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
