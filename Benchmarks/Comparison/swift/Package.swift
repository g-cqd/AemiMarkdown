// swift-tools-version: 6.4
import PackageDescription

// The Swift engines of the comparison (Benchmarks/Comparison): AemiMarkdown, swift-markdown, cmark-gfm itself and Foundation's own Markdown. Not part of the library; release only.
let package = Package(
    name: "CompareSwift",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../.."),
        .package(path: "../../../Apps/MarkdownLook"),
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            revision: "ea1d88be47afe8a731b3971d7b3fb7a3a6db1a5a"
        )
    ],
    targets: [
        .executableTarget(
            name: "CompareSwift",
            dependencies: [
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "MarkdownLookKit", package: "MarkdownLook"),
                .product(name: "Markdown", package: "swift-markdown")
            ]
        )
    ]
)
