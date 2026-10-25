// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Panerail",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LayoutEngine"),
        .target(name: "PanerailCore", dependencies: ["LayoutEngine"]),
        .executableTarget(
            name: "PanerailApp",
            dependencies: ["LayoutEngine", "PanerailCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "LayoutEngineTests", dependencies: ["LayoutEngine"]),
        .testTarget(
            name: "PanerailCoreTests",
            dependencies: ["PanerailCore", "LayoutEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
