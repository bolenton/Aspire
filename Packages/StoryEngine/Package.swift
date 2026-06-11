// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StoryEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StoryEngine", targets: ["StoryEngine"])
    ],
    targets: [
        .target(name: "StoryEngine"),
        .testTarget(name: "StoryEngineTests", dependencies: ["StoryEngine"])
    ]
)
