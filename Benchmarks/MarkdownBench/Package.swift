// swift-tools-version: 6.4
import PackageDescription

// Not part of the library: the numbers AemiMarkdown is held to (ask's roadmap 0065, phase 0): throughput, allocations per KB, and the cost of streaming a long
// answer in small deltas, on a corpus of real assistant messages, against swift-markdown's baseline. Release only: `swift run -c release MarkdownBench corpus.ndjson`.
let package = Package(
    name: "MarkdownBench",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "785c6b25cb3f4dc16ca2334fd69428fae4ee0b01")
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
