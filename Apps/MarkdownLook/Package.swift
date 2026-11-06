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
        .package(url: "https://github.com/g-cqd/AemiHMMML.git", revision: "4d3e071072019540c43cbee10073f54664fd6ebe"),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "5aa84e0eca14c344f4fc0b313dbb907dc1446b9e"),
        .package(url: "https://github.com/g-cqd/AemiMermaid.git", revision: "aa8314521eb5f16633ee45e79515192f4e23c7af"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "0bae2edb1a89bd3d931fb3122c2184cc5c368834")
    ],
    targets: [
        .target(
            name: "MarkdownLookKit",
            dependencies: [
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiFrontMatter", package: "AemiHMMML"),
                .product(name: "AemiHMMML", package: "AemiHMMML"),
                .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "AemiKernel", package: "aemi"),
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
