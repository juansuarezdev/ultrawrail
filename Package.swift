// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ultrawrail",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LayoutEngine"),
        .target(name: "UltrawrailCore", dependencies: ["LayoutEngine"]),
        .executableTarget(
            name: "UltrawrailApp",
            dependencies: ["LayoutEngine", "UltrawrailCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine"]),
        .testTarget(
            name: "UltrawrailCoreTests",
            dependencies: ["UltrawrailCore", "LayoutEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
