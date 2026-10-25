import Testing

@testable import AemiMarkdown

/// Feeding a document in pieces gives the document that parsing it whole gives (ADR-0001, decisions 3 and 4).
@Suite("A streamed document is the document parsed whole")
struct StreamingTests {
    /// Examples without a link reference definition: a definition that comes after a link reaches it only when the document is parsed whole.
    static let examples: [SpecExample] = SpecConformanceTests.examples.filter { !$0.markdown.contains("]:") }

    private func extensions(_ example: SpecExample) -> MarkdownExtensions { example.file == "commonmark" ? [] : .all }

    private func html(_ document: MarkdownDocument) -> String { SpecHTMLRenderer.html(of: document) }

    private func chunks(of bytes: [UInt8], size: Int) -> [[UInt8]] {
        stride(from: 0, to: bytes.count, by: size).map { Array(bytes[$0 ..< Swift.min($0 + size, bytes.count)]) }
    }

    @Test(arguments: [1, 3, 7])
    func `pieces appended and finished give the whole parse`(size: Int) {
        for example in Self.examples {
            let bytes = Array(example.markdown.utf8)
            var parser = MarkdownParser(extensions: extensions(example))
            for piece in chunks(of: bytes, size: size) { parser.append(piece) }
            parser.finish()
            #expect(
                html(parser.snapshot()) == html(MarkdownParser.parse(bytes, extensions: extensions(example))),
                "\(example.id) in pieces of \(size)")
        }
    }

    @Test(arguments: [1, 5])
    func `a snapshot after each piece is the parse of what has arrived`(size: Int) {
        for example in Self.examples {
            let bytes = Array(example.markdown.utf8)
            var parser = MarkdownParser(extensions: extensions(example))
            var arrived: [UInt8] = []
            for piece in chunks(of: bytes, size: size) {
                parser.append(piece)
                arrived += piece
                #expect(
                    html(parser.snapshot()) == html(MarkdownParser.parse(arrived, extensions: extensions(example))),
                    "\(example.id) after \(arrived.count) of \(bytes.count) bytes")
            }
        }
    }

    @Test func `blocks that closed do not change when more arrives`() {
        var parser = MarkdownParser()
        parser.append(Array("# Title\n\nFirst paragraph.\n\n- one\n- two\n".utf8))
        let before = parser.snapshot()
        let closed = before.blocks.committed
        #expect(!closed.isEmpty)
        parser.append(Array("\nSecond paragraph, still open".utf8))
        let after = parser.snapshot()
        #expect(after.blocks.committed.starts(with: closed))
        #expect(html(after).contains("<p>Second paragraph, still open</p>"))
    }

    @Test func `a carriage return at the end of a piece waits for the line feed that may follow`() {
        var parser = MarkdownParser()
        parser.append(Array("a\r".utf8))
        parser.append(Array("\nb".utf8))
        parser.finish()
        #expect(html(parser.snapshot()) == "<p>a\nb</p>\n")
    }
}
