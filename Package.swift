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

// Test-only dependencies that are not published (AemiRegex has no remote yet) or that consumers should never resolve are
// gated behind AEMIMARKDOWN_DEV, as AemiJSON gates its own. A plain `swift build` and `swift test` need none of them.
let isDev = Context.environment["AEMIMARKDOWN_DEV"] != nil

// One revision of Aemi for the whole graph: SwiftPM rejects one package identity at two revisions. ask, TerminalKit and
// AemiJSON pin the same one, so they move together.
let aemiDependency: Package.Dependency = .package(
    url: "https://github.com/Aemi-Studio/aemi.git", revision: "4f270e05473accace718446ee31c7b03d60a61ae")

var packageDependencies: [Package.Dependency] = [aemiDependency]
var devTestDependencies: [Target.Dependency] = []
if isDev {
    // The spec's raw-HTML and autolink grammars are regular; AemiRegex runs them as the oracle for the hand-written byte
    // scanners (differential tests). It is never on the parse path: it takes an Array, and a search costs more than a scan.
    packageDependencies.append(.package(path: "../aemiregex"))
    devTestDependencies.append(.product(name: "AemiRegex", package: "aemiregex"))
}

let package = Package(
    name: "AemiMarkdown",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [.library(name: "AemiMarkdown", targets: ["AemiMarkdown"])],
    dependencies: packageDependencies,
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
            ] + devTestDependencies,
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings)
    ]
)
