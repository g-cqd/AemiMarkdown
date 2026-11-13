// swift-tools-version: 6.4
import PackageDescription

// MarkdownLook's tools and the tests of its kit (ask roadmaps 0199, 0201). The kit itself, MarkdownLookKit, is a product of the package
// two folders up since ADR-0008 (Sunset pins it by revision); its sources stay here, in Sources/MarkdownLookKit. The apps (Xcode projects made
// by XcodeGen from project.yml) link the kit from that package.
let package = Package(
    name: "MarkdownLook",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "markdown-look-html", targets: ["markdown-look-html"]),
        .executable(name: "markdown-look-compare", targets: ["markdown-look-compare"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "0bae2edb1a89bd3d931fb3122c2184cc5c368834")
    ],
    targets: [
        .executableTarget(
            name: "markdown-look-html",
            dependencies: [.product(name: "MarkdownLookKit", package: "AemiMarkdown")]
        ),
        // A tool for the work on the native view: the same page in WebKit and in SwiftUI, side by side, with how alike they are.
        .executableTarget(
            name: "markdown-look-compare",
            dependencies: [
                .product(name: "MarkdownLookKit", package: "AemiMarkdown"),
                .product(name: "AemiMarkdown", package: "AemiMarkdown")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MarkdownLookKitTests",
            dependencies: [
                .product(name: "MarkdownLookKit", package: "AemiMarkdown"),
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiTestKit", package: "aemi"), .product(name: "AemiIO", package: "aemi")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6), .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        )
    ]
)
