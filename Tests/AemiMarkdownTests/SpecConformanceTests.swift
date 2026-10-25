import Foundation
import Synchronization
import Testing

@testable import AemiMarkdown

/// Every example of CommonMark 0.31.2 and of the GitHub extensions the project supports, parsed and rendered as the spec's HTML.
@Suite("The parser agrees with the specification")
struct SpecConformanceTests {
    /// Chapters of `extensions.txt` that are in scope. The others (tag filter, footnotes, task lists, interop) are not built, and are not run.
    static let supportedChapters: Set<String> = ["Tables", "Strikethroughs", "Autolinks"]

    static let examples: [SpecExample] = {
        let core = (try? SpecFile.load("commonmark")) ?? []
        let extensions = ((try? SpecFile.load("extensions")) ?? []).filter { supportedChapters.contains($0.chapter) }
        return core + extensions
    }()

    @Test func `the fixture files are all there`() throws {
        #expect(try SpecFile.load("commonmark").count == 652)
        #expect(try SpecFile.load("extensions").count == 30)
    }

    @Test(arguments: examples)
    func `an example renders as the spec says, or is on the ratchet`(example: SpecExample) throws {
        let known = try SpecRatchet.knownFailing()
        let document = MarkdownParser.parse(Array(example.markdown.utf8))
        let html = SpecHTMLRenderer.html(of: document)
        let passes = html == example.html
        if let proposal = ProcessInfo.processInfo.environment["AEMIMARKDOWN_RATCHET_PROPOSAL"], !passes {
            try Self.record("\(example.id) # \(example.section)\n", in: proposal)
        }
        if let report = ProcessInfo.processInfo.environment["AEMIMARKDOWN_REPORT"], !passes {
            try Self.record(
                "## \(example.id) (\(example.section))\n\(example.markdown.debugDescription)\nexpected \(example.html.debugDescription)\nactual   \(html.debugDescription)\n\n",
                in: report)
        }
        #expect(
            passes == !known.contains(example.id),
            "\(example.id) \(passes ? "passes but is listed in known-failing.txt" : "fails and is not listed")\nmarkdown: \(example.markdown.debugDescription)\nexpected: \(example.html.debugDescription)\nactual:   \(html.debugDescription)"
        )
    }

    private static let proposalLock = Mutex(())
    /// Appends `line` to a file named by the environment: the ratchet proposal for `Scripts/update-ratchet.sh`, or a report of failures.
    private static func record(_ line: String, in path: String) throws {
        try proposalLock.withLock { _ in
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try line.write(toFile: path, atomically: false, encoding: .utf8)
            }
        }
    }
}
