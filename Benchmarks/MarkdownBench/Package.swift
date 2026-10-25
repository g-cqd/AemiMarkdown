// swift-tools-version: 6.4
import PackageDescription

// Not part of the library: the numbers AemiMarkdown is held to (ask's roadmap 0065, phase 0): throughput, allocations per KB, and the cost of streaming a long
// answer in small deltas, on a corpus of real assistant messages, against swift-markdown's baseline. Release only: `swift run -c release MarkdownBench corpus.ndjson`.
let package = Package(
    name: "MarkdownBench",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "e0c5d36ed0075922b2d613fdcacfc4b01434a159")
    ],
    targets: [
        .executableTarget(
            name: "MarkdownBench",
            dependencies: [
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "CAemiTestKitMalloc", package: "aemi")
            ])
    ]
)
