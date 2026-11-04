import AemiMarkdown
import Foundation
import Testing

@testable import MarkdownLookKit

/// The public documents of the corpus (`Benchmarks/Corpus/fetch.py setup` in AemiMarkdown) as pages: each balanced, none with a script or a link that runs.
@Suite("Public documents as pages")
struct CorpusTests {
    static let directory: String = {
        let base =
            ProcessInfo.processInfo.environment["AEMI_MARKDOWN_CORPUS"]
            ?? NSString(string: "~/Library/Caches/AemiMarkdownCorpus").expandingTildeInPath
        return base + "/files"
    }()

    static var documents: [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
        return names.filter {
            (try? FileManager.default.attributesOfItem(atPath: directory + "/" + $0)[.size] as? Int ?? 0) ?? 0 < 400_000
        }
    }

    @Test(
        .enabled(
            if: !documents.isEmpty,
            "the public corpus is not set up: run Benchmarks/Corpus/fetch.py setup in AemiMarkdown"
        )
    )
    func `every public document is a balanced page without script`() throws {
        var failures: [String] = []
        var diagrams = 0
        for name in Self.documents {
            guard let data = FileManager.default.contents(atPath: Self.directory + "/" + name) else { continue }
            let page = MarkdownHTMLRenderer().page(MarkdownParser.parse(Array(data)), title: name)
            if let problem = TagBalance.problem(in: page) { failures.append("\(name): \(problem)") }
            if page.contains("<script") || page.contains("href=\"javascript:") || page.contains("onerror=") {
                failures.append("\(name): active content")
            }
            diagrams += page.components(separatedBy: "<figure>").count - 1
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
        #expect(diagrams > 0, "no corpus document had a diagram drawn")
    }
}
