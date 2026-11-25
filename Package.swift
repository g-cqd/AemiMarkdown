// swift-tools-version: 6.4
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let kernelSettings: [SwiftSetting] = strictSettings + [.strictMemorySafety()]

let aemiDependency: Package.Dependency = .package(
    url: "https://github.com/Aemi-Studio/aemi.git",
    revision: "bd5e4cf4441ca3ed1b424935142586ccaac0f835"
)
let hmmmlDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiHMMML.git",
    revision: "77dc8e23456150cd47bab269b785fcbf7ca29e00"
)
let regexDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiRegex.git",
    revision: "2df69da6f7b8086ae07272d4368d45fe1fd57160"
)

#if os(macOS)
    let lookDependencies: [Package.Dependency] = [
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "1c098f0456a2f86dee32dfd9b85455980216589f"),
        .package(url: "https://github.com/g-cqd/AemiMermaid.git", revision: "7bbd801f8ed3229f95ddae0ae6fc45824f5e9f39"),
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
