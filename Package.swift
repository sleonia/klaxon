// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Klaxon",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "KlaxonKit",
            path: "Sources/KlaxonKit"
        ),
        .executableTarget(
            name: "Klaxon",
            dependencies: ["KlaxonKit"],
            path: "Sources/Klaxon"
        ),
        .testTarget(
            name: "KlaxonTests",
            dependencies: ["KlaxonKit"],
            path: "Tests/KlaxonTests"
        ),
    ]
)
