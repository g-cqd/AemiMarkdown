// swift-tools-version: 6.4
import PackageDescription

// The viewer kit of MarkdownLook (ask roadmaps 0199, 0201): a Markdown document as HTML, with its Mermaid diagrams as SVG. A sub-package of its own, like Benchmarks/MarkdownBench: the apps
// (Xcode projects made by XcodeGen from project.yml) link this and nothing else of ours. Paths while the packages are developed side by side; revisions at landing.
let package = Package(
    name: "MarkdownLook",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MarkdownLookKit", targets: ["MarkdownLookKit"]),
        .executable(name: "markdown-look-html", targets: ["markdown-look-html"]),
        .executable(name: "markdown-look-compare", targets: ["markdown-look-compare"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/g-cqd/AemiMermaid.git", revision: "488edea83ef3990cdf712cdd54b1e514d4621655"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "2b2dbe6d0bc3dcb5ec48093c02a2e279d03a37a8")
    ],
    targets: [
        .target(
            name: "MarkdownLookKit",
            dependencies: [
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiLexers", package: "aemi"),
                .product(name: "AemiMermaidSyntax", package: "AemiMermaid"),
                .product(name: "AemiMermaidScene", package: "AemiMermaid"),
                .product(name: "AemiMermaidLayout", package: "AemiMermaid"),
                .product(name: "AemiMermaidSVG", package: "AemiMermaid")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6), .treatAllWarnings(as: .error), .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"), .enableUpcomingFeature("MemberImportVisibility"),
                .strictMemorySafety()
            ]
        ),
        .executableTarget(name: "markdown-look-html", dependencies: ["MarkdownLookKit"]),
        // A tool for the work on the native view: the same page in WebKit and in SwiftUI, side by side, with how alike they are.
        .executableTarget(
            name: "markdown-look-compare",
            dependencies: ["MarkdownLookKit", .product(name: "AemiMarkdown", package: "AemiMarkdown")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MarkdownLookKitTests",
            dependencies: [
                "MarkdownLookKit", .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6), .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        )
    ]
)
