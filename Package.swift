// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LimitPeek",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LimitPeek",
            path: "Sources/LimitPeek",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LimitPeekTests",
            dependencies: ["LimitPeek"],
            path: "Tests/LimitPeekTests",
            resources: [.process("Fixtures")]
        )
    ]
)
