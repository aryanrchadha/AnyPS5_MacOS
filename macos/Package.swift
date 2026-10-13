// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnyPS5Studio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AnyPS5Studio",
            path: "Sources/AnyPS5Studio"
        ),
        .testTarget(
            name: "AnyPS5StudioTests",
            dependencies: ["AnyPS5Studio"],
            path: "Tests/AnyPS5StudioTests"
        ),
    ]
)
