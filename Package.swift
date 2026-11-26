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
    revision: "1567137e2c810eb489facf29d90a2c623b75d604"
)
let hmmmlDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiHMMML.git",
    revision: "dd439204570a9969612ea009608ec39e455c6a33"
)
let regexDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiRegex.git",
    revision: "792eebdcdf3a47daf8ba6ae9a1dfd4c6c5833fc4"
)

#if os(macOS)
    let lookDependencies: [Package.Dependency] = [
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "75deac170071149540c436bdab47a5c6d5520a4a"),
        .package(url: "https://github.com/g-cqd/AemiMermaid.git", revision: "14bc98fdf9e9e29cc14c0dc4a319688bd25d1b27"),
        .package(url: "https://github.com/g-cqd/AemiTextUI.git", revision: "aebc2c6341367ee06f6fdc4a91fe81d41a12deee")
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
