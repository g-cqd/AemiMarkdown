import Foundation
import Testing

@testable import AemiMarkdown

/// A code block's language and lines, read without copying (ask roadmap 0202).
@Suite("The fence reader gives a code block's language and lines")
struct FenceReaderTests {
    private struct Read {
        var header: MarkdownFenceReader.Header
        var language: String
        var info: String
        var lines: [String]
        var spaces: [Int]
    }

    private func read(_ markdown: String, block ordinal: Int = 0, extensions: MarkdownExtensions = .github) -> Read? {
        let document = MarkdownParser.parse(Array(markdown.utf8), extensions: extensions)
        guard let block = document.block(at: ordinal) else { return nil }
        var reader = MarkdownFenceReader()
        guard let header = reader.read(block, in: document) else { return nil }
        func text(_ range: Range<Int>) -> String { String(decoding: document.source[range], as: UTF8.self) }
        return Read(
            header: header,
            language: text(header.language),
            info: text(header.info),
            lines: reader.lines.map { text($0.range) },
            spaces: reader.lines.map(\.spacesFromTab)
        )
    }

    @Test func `a backtick fence gives its language, its lines and that it closed`() throws {
        let found = try #require(read("```mermaid\nflowchart TD\n  A-->B\n```\n"))
        #expect(found.header.style == .backtick && found.header.isClosed == true)
        #expect(found.language == "mermaid" && found.info == "mermaid")
        #expect(found.lines == ["flowchart TD", "  A-->B"])
    }

    @Test func `a tilde fence is read the same way`() throws {
        let found = try #require(read("~~~ rust\nfn main() {}\n~~~\n"))
        #expect(
            found.header.style == .tilde && found.header.isClosed == true && found.language == "rust"
                && found.lines == ["fn main() {}"]
        )
    }

    @Test func `the language is the first word of the info string, which keeps what follows it`() throws {
        let found = try #require(read("```mermaid title=\"x\" theme=dark\ngraph\n```\n"))
        #expect(found.language == "mermaid" && found.info == "mermaid title=\"x\" theme=dark")
    }

    @Test func `a fence with no info string has an empty language`() throws {
        let found = try #require(read("```\ncode\n```\n"))
        #expect(found.language.isEmpty && found.info.isEmpty && found.lines == ["code"])
    }

    @Test func `a fence the input ended inside is not closed, and runs to the end`() throws {
        let found = try #require(read("```swift\nlet a = 1\n\nlet b = 2"))
        #expect(found.header.isClosed == false && found.lines == ["let a = 1", "", "let b = 2"])
    }

    @Test func `a fence with nothing in it has no lines and is closed`() throws {
        let found = try #require(read("```\n```\n"))
        #expect(found.header.isClosed == true && found.lines.isEmpty)
        #expect(try #require(read("```")).header.isClosed == false)
    }

    @Test func `a closing fence needs as many characters as the opening one and nothing after them`() throws {
        #expect(try #require(read("````\ncode\n```\n")).header.isClosed == false, "three do not close four")
        #expect(try #require(read("````\ncode\n`````  \n")).header.isClosed == true, "five do, with white space after")
        #expect(try #require(read("~~~\ncode\n```\n")).header.isClosed == false, "backticks do not close tildes")
        #expect(
            try #require(read("```\ncode\n``` x\n")).header.isClosed == false,
            "text after the closing run: it is a code line"
        )
    }

    @Test func `an indented code block has lines and no language`() throws {
        let found = try #require(read("    one\n    two\n"))
        #expect(
            found.header.style == .indented && found.header.isClosed == true && found.language.isEmpty
                && found.lines == ["one", "two"]
        )
    }

    /// Walks a document and reads every code block, nested or not, as a renderer walking its events does.
    private func readAll(_ markdown: String) -> [Read] {
        let document = MarkdownParser.parse(Array(markdown.utf8))
        var reader = MarkdownFenceReader()
        var events = document.events
        var all: [Read] = []
        func text(_ range: Range<Int>) -> String { String(decoding: document.source[range], as: UTF8.self) }
        while let event = events.next() {
            guard case .enter(let node) = event, node.kind == .codeBlock,
                let header = reader.read(node, from: &events, in: document)
            else { continue }
            all.append(
                Read(
                    header: header,
                    language: text(header.language),
                    info: text(header.info),
                    lines: reader.lines.map { text($0.range) },
                    spaces: reader.lines.map(\.spacesFromTab)
                )
            )
        }
        return all
    }

    @Test
    func
        `a fence inside a block quote or a list item is read from its events, without its container's prefix, and its closing is not known`()
        throws
    {
        let inQuote = try #require(readAll("> ```swift\n> let a = 1\n> ```\n").first)
        #expect(
            inQuote.language == "swift" && inQuote.lines == ["let a = 1"] && inQuote.header.isClosed == nil
                && inQuote.header.style == .backtick
        )
        let inItem = try #require(readAll("1. one\n\n   ~~~sh\n   ls\n   ~~~\n").first)
        #expect(inItem.language == "sh" && inItem.lines == ["ls"] && inItem.header.style == .tilde)
        #expect(readAll("- a\n- b\n\n  ```\n  x\n  ```\n").first?.lines == ["x"])
        #expect(
            readAll("> ~~~\n> y\n> ~~~\n").first?.header.style == .tilde,
            "no info string: the style is found from the line before the code"
        )
    }

    @Test func `a line a tab was split across keeps the spaces the tab left`() throws {
        let split = try #require(readAll("-\t```\n\tcode\n\t```\n").first)
        #expect(split.lines.count == 1 && split.spaces.count == 1)
        let found = try #require(read("```\n\tindented\n```\n"))
        #expect(found.lines == ["\tindented"] && found.spaces == [0])
    }

    @Test func `two code blocks in one walk are read one after the other`() {
        #expect(readAll("```a\n1\n```\n\n> ```b\n> 2\n> ```\n").map(\.language) == ["a", "b"])
    }

    @Test func `something that is not a code block is not read`() {
        #expect(read("# heading\n") == nil)
        #expect(read("paragraph\n") == nil)
    }

    @Test func `carriage returns and line feeds end lines the same way`() throws {
        let found = try #require(read("```js\r\na\r\nb\r\n```\r\n"))
        #expect(found.header.isClosed == true && found.lines == ["a", "b"])
    }

    @Test func `every example of the specifications: the lines, joined, are the code the specification's HTML shows`() {
        for example in SpecConformanceTests.examples where example.html.components(separatedBy: "<pre><code").count == 2
        {
            let extensions: MarkdownExtensions = example.file == "commonmark" ? [] : .github
            let document = MarkdownParser.parse(Array(example.markdown.utf8), extensions: extensions)
            var reader = MarkdownFenceReader()
            var found: [String]?
            for block in document.topLevelBlocks where reader.read(block, in: document) != nil {
                found = reader.lines.map {
                    String(repeating: " ", count: $0.spacesFromTab)
                        + String(decoding: document.source[$0.range], as: UTF8.self)
                }
            }
            // Only a top-level code block is read here; an example whose code block is inside a container has none.
            guard let lines = found else { continue }
            let body = example.html.components(separatedBy: "<pre><code")[1].components(separatedBy: "</code></pre>")[0]
            let code = String(body.drop { $0 != ">" }.dropFirst())
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
            #expect(code == (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"), "\(example.id)")
        }
    }

    @Test func `a reader that is reused gives each block its own lines`() throws {
        let document = MarkdownParser.parse(Array("```a\none\ntwo\n```\n\n```b\nthree\n```\n".utf8))
        var reader = MarkdownFenceReader()
        let blocks = Array(document.topLevelBlocks)
        _ = reader.read(blocks[0], in: document)
        #expect(reader.lines.count == 2)
        _ = reader.read(blocks[1], in: document)
        #expect(reader.lines.count == 1)
    }
}
