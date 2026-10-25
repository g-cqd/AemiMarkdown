import Foundation
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

    /// Found by the model in docs/formal/LineSplitter.tla: a carriage return at the end of the input is a line ending, not a character of the last line.
    @Test(arguments: ["a\r", "a\r\r", "a\n\r", "# h\r", "- a\r"])
    func `a carriage return at the end of the input ends its line`(input: String) {
        let whole = html(MarkdownParser.parse(Array(input.utf8)))
        #expect(!whole.contains("\r"), "whole: \(whole.debugDescription)")
        var parser = MarkdownParser()
        parser.append(Array(input.utf8))
        #expect(!html(parser.snapshot()).contains("\r"), "snapshot")
        parser.finish()
        #expect(html(parser.snapshot()) == whole)
        #expect(html(MarkdownParser.parse(Array(input.replacingOccurrences(of: "\r", with: "\n").utf8))) == whole)
    }
}

/// A snapshot shares the committed part of the tapes and writes nothing to it: a write to storage that a snapshot shares copies all of it, so a
/// snapshot of a long document would cost the document (docs/formal/SnapshotProtocol.tla states the rule; the first implementation broke it).
@Suite("A snapshot does not copy the closed part of the document")
struct SnapshotSharingTests {
    private func address(_ tape: SlotTape) -> UInt? {
        tape.committed.withUnsafeBufferPointer { $0.baseAddress.map { UInt(bitPattern: $0) } }
    }

    @Test(arguments: ["  ", "\t", "> ", "# ", "- ", "```", "text"])
    func `snapshots with a partial line share the committed tapes`(partial: String) {
        var parser = MarkdownParser()
        let closed = (0 ..< 200).map { "# heading \($0)\n\nparagraph \($0)\n\n" }.joined()
        parser.append(Array((closed + "an open paragraph\n").utf8))
        parser.append(Array(partial.utf8))
        let before = address(parser.blocks)
        #expect(before != nil)
        let document = parser.snapshot()
        #expect(address(document.blocks) == before, "the snapshot copied the committed block tape")
        #expect(address(parser.blocks) == before, "the parser's own tape moved")
    }
}
