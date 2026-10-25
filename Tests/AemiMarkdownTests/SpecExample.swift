import Foundation
import Testing

/// One example of a specification file: Markdown in, the reference HTML out.
struct SpecExample: Sendable, Hashable, CustomTestStringConvertible {
    /// `commonmark` or `extensions`.
    var file: String
    /// 1-based, in file order, as the spec's own numbering counts them.
    var number: Int
    /// The `##` heading it sits under.
    var chapter: String
    /// The nearest heading above it.
    var section: String
    var markdown: String
    var html: String

    /// The ratchet's key.
    var id: String { "\(file) \(number)" }
    var testDescription: String { "\(id) (\(section))" }
}

/// Reads the examples out of a specification file. Its format: a line of 32 backticks and `example` opens one; a line
/// holding only `.` divides the Markdown from the HTML; 32 backticks close it. `→` stands for a tab.
enum SpecFile {
    private static let fence = String(repeating: "`", count: 32)

    static func load(_ file: String) throws -> [SpecExample] {
        let name = file == "commonmark" ? "commonmark-0.31.2" : file
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        var examples: [SpecExample] = []
        var chapter = ""
        var section = ""
        var markdown: [Substring] = []
        var html: [Substring] = []
        enum Phase { case outside, markdown, html }
        var phase = Phase.outside
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            switch phase {
                case .outside:
                    if line.hasPrefix(fence + " example") {
                        phase = .markdown
                        markdown = []
                        html = []
                    } else if line.hasPrefix("## ") {
                        chapter = String(line.dropFirst(3))
                        section = chapter
                    } else if line.hasPrefix("### ") {
                        section = String(line.dropFirst(4))
                    }
                case .markdown:
                    if line == "." { phase = .html } else { markdown.append(line) }
                case .html:
                    if line == fence {
                        phase = .outside
                        examples.append(
                            SpecExample(
                                file: file, number: examples.count + 1, chapter: chapter, section: section,
                                markdown: Self.join(markdown), html: Self.join(html)))
                    } else {
                        html.append(line)
                    }
            }
        }
        return examples
    }

    /// Each line ends in a line feed, as the spec's examples do.
    private static func join(_ lines: [Substring]) -> String {
        lines.map { $0.replacingOccurrences(of: "→", with: "\t") + "\n" }.joined()
    }
}
