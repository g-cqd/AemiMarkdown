// swift-tools-version: 6.4
import PackageDescription

// A tool, not part of the library: it reads the WHATWG `entities.json` with AemiJSON (the Foundation-free core) and writes the entity table the parser
// looks names up in. Run: swift run -c release GenerateEntities entities.json > ../../Sources/AemiMarkdown/Generated/EntityTable+Data.swift
let package = Package(
    name: "GenerateEntities",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../../AemiJSON")],
    targets: [
        .executableTarget(
            name: "GenerateEntities",
            dependencies: [.product(name: "AemiJSONCore", package: "AemiJSON")])
    ]
)
