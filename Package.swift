// swift-tools-version: 6.4
import PackageDescription

// Swift 6 language mode, warnings as errors, and the upcoming features that tighten existentials and imports. No unsafe
// flags, so the library can be consumed through a version-pinned requirement. Same strictness as AemiJSON and AemiRegex.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

// The parser reads attacker-controlled bytes (a model's answer, a fetched page), so every unsafe construct in it is marked
// `unsafe` and justified where it stands.
let kernelSettings: [SwiftSetting] = strictSettings + [.strictMemorySafety()]

// AemiRegex compiles the spec's own grammars for the differential tests of the hand-written scanners (ADR-0001, decision 7). A test-only
// dependency: a package that depends on AemiMarkdown does not fetch it.
let aemiDependency: Package.Dependency = .package(
    url: "https://github.com/Aemi-Studio/aemi.git",
    revision: "0bae2edb1a89bd3d931fb3122c2184cc5c368834"
)
// AemiHMMML's front matter locator and readers (its ADR-0009 and ADR-0015), for `MarkdownExtensions.frontMatter`.
let hmmmlDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiHMMML.git",
    revision: "ed8469a6b6893265ad8ceede6f7fee00d3169e88"
)
let regexDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiRegex.git",
    revision: "3efa8699dbce4cafe5efc6dcf76223890cf06c1e"
)

// MarkdownLookKit, the viewer and editor kit (ADR-0008): of MarkdownLook, and of Sunset's Markdown pane, which pins this package by
// revision. It is AppKit and SwiftUI, for macOS 26 and later, so it exists only when the manifest is read on a Mac: a Linux build
// has neither the target nor what it alone depends on (Mermaid for fences, AemiJSON for a head's table, AemiTextUI for code).
#if os(macOS)
    let lookDependencies: [Package.Dependency] = [
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "806b481d8cc7e21f07d45537b625c5ac9abfc87e"),
        .package(url: "https://github.com/g-cqd/AemiMermaid.git", revision: "9941c3862e0a898a91eafddbf131543a733c37d7"),
        .package(url: "https://github.com/g-cqd/AemiTextUI.git", revision: "4b64bf4ea295d3ea68ceaa9ca2360beb7f5b0a3d")
    ]
    let lookProducts: [Product] = [.library(name: "MarkdownLookKit", targets: ["MarkdownLookKit"])]
    let lookTargets: [Target] = [
        .target(
            name: "MarkdownLookKit",
            dependencies: [
                "AemiMarkdown",
                .product(name: "AemiFrontMatter", package: "AemiHMMML"),
                .product(name: "AemiHMMML", package: "AemiHMMML"),
                .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiLexers", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi"),
                .product(name: "AemiTextStyling", package: "AemiTextUI"),
                .product(name: "AemiMermaidSyntax", package: "AemiMermaid"),
                .product(name: "AemiMermaidScene", package: "AemiMermaid"),
                .product(name: "AemiMermaidLayout", package: "AemiMermaid"),
                .product(name: "AemiMermaidSVG", package: "AemiMermaid")
            ],
            path: "Apps/MarkdownLook/Sources/MarkdownLookKit",
            // As the kit was built in its own package: the parser's settings without the inferred isolated conformances.
            swiftSettings: [
                .swiftLanguageMode(.v6), .treatAllWarnings(as: .error), .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"), .enableUpcomingFeature("MemberImportVisibility"),
                .strictMemorySafety()
            ]
        )
    ]
#else
    let lookDependencies: [Package.Dependency] = []
    let lookProducts: [Product] = []
    let lookTargets: [Target] = []
#endif

// The DocC plugin is for contributors (`AEMIMARKDOWN_DEV=1 swift package generate-documentation --target AemiMarkdown`); packages that depend on
// AemiMarkdown never resolve it.
let documentationDependencies: [Package.Dependency] =
    Context.environment["AEMIMARKDOWN_DEV"] != nil
    ? [.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0")] : []

let package = Package(
    name: "AemiMarkdown",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [.library(name: "AemiMarkdown", targets: ["AemiMarkdown"])] + lookProducts,
    dependencies: [aemiDependency, hmmmlDependency, regexDependency] + lookDependencies + documentationDependencies,
    targets: [
        .target(
            name: "AemiMarkdown",
            dependencies: [
                .product(name: "AemiFrontMatter", package: "AemiHMMML"),
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi")
            ],
            swiftSettings: kernelSettings
        ),
        .testTarget(
            name: "AemiMarkdownTests",
            dependencies: [
                "AemiMarkdown",
                .product(name: "AemiFrontMatter", package: "AemiHMMML"),
                .product(name: "AemiHMMMLCore", package: "AemiHMMML"),
                .product(name: "AemiTOML", package: "AemiHMMML"),
                .product(name: "AemiYAML", package: "AemiHMMML"),
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AemiMarkdownGrammarTests",
            dependencies: ["AemiMarkdown", .product(name: "AemiRegex", package: "AemiRegex")],
            swiftSettings: strictSettings
        )
    ] + lookTargets
)
