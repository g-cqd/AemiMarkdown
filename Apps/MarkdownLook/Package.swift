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
        .package(path: "../../../AemiTextUI"),
        // A document's head drawn as a table: AemiHMMML's front matter reader and JSON projection, at the revisions AemiMarkdown pins.
        .package(url: "https://github.com/g-cqd/AemiHMMML.git", revision: "326db8babb157297d1686b4808dc3b9d86a1d385"),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "aec8895f1bc9bdaf2104b0d0ebe91e4a93b3c374"),
        .package(url: "https://github.com/g-cqd/AemiMermaid.git", revision: "1a272f8835a9026cde79e8214ad490070a847774"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "e30aad82377cbea62171cc722a88041e97021db2")
    ],
    targets: [
        .target(
            name: "MarkdownLookKit",
            dependencies: [
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiFrontMatter", package: "AemiHMMML"),
                .product(name: "AemiHMMML", package: "AemiHMMML"),
                .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "AemiLexers", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi"),
                .product(name: "AemiTextStyling", package: "AemiTextUI"),
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
