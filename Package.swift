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
    url: "https://github.com/Aemi-Studio/aemi.git", revision: "04e49d108e43a94fac449f344bfca9eabc5be0e9")
let regexDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiRegex.git", revision: "923d23f493a161ca8ca630e8b3f982c5fc2f69da")

// The DocC plugin is for contributors (`AEMIMARKDOWN_DEV=1 swift package generate-documentation --target AemiMarkdown`); packages that depend on
// AemiMarkdown never resolve it.
let documentationDependencies: [Package.Dependency] =
    Context.environment["AEMIMARKDOWN_DEV"] != nil
    ? [.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0")] : []

let package = Package(
    name: "AemiMarkdown",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [.library(name: "AemiMarkdown", targets: ["AemiMarkdown"])],
    dependencies: [aemiDependency, regexDependency] + documentationDependencies,
    targets: [
        .target(
            name: "AemiMarkdown",
            dependencies: [
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi")
            ],
            swiftSettings: kernelSettings),
        .testTarget(
            name: "AemiMarkdownTests",
            dependencies: [
                "AemiMarkdown",
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings),
        .testTarget(
            name: "AemiMarkdownGrammarTests",
            dependencies: ["AemiMarkdown", .product(name: "AemiRegex", package: "AemiRegex")],
            swiftSettings: strictSettings)
    ]
)
