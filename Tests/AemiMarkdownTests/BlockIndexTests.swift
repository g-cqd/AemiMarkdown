import Foundation
import Testing

@testable import AemiMarkdown

/// A top-level block knows its source and what it is, by its bytes, and a renderer can start a walk at any block (ADR-0003, ask roadmap 0203).
@Suite("Top-level blocks have a source range, a content hash and an ordinal")
struct BlockIndexTests {
    private func parse(_ text: String, extensions: MarkdownExtensions = .github) -> MarkdownDocument {
        MarkdownParser.parse(Array(text.utf8), extensions: extensions)
    }

    private func texts(of document: MarkdownDocument) -> [String] {
        document.topLevelBlocks.map { String(decoding: document.source[$0.sourceRange], as: UTF8.self) }
    }

    /// The block structure of one block, without its inlines and without where its bytes are: what parsing the block's own bytes must give back.
    private func structure(_ document: MarkdownDocument, _ block: MarkdownBlock) -> [String] {
        var result: [String] = []
        var leaf: NodeKind?
        for event in document.events(of: block) {
            switch event {
                case .enter(let node):
                    if leaf != nil { continue }
                    result.append("enter \(node.kind) \(node.payload)")
                    if [.paragraph, .heading, .tableCell].contains(node.kind) { leaf = node.kind }
                case .exit(let node):
                    if let open = leaf, open == node.kind {
                        leaf = nil
                    } else if leaf == nil {
                        result.append("exit \(node.kind)")
                    }
                    if leaf == nil, [.paragraph, .heading, .tableCell].contains(node.kind) {
                        result.append("exit \(node.kind)")
                    }
                case .leaf(let node):
                    if leaf == nil {
                        result.append("leaf \(node.kind) \(node.payload) \(node.range.count) \(node.value)")
                    }
            }
        }
        return result
    }

    @Test func `a block's source is its own text, from its first line to its last byte of text`() {
        let document = parse("# Title\n\nA paragraph.\n\n- one\n- two\n\n```\ncode\n```\n")
        #expect(texts(of: document) == ["# Title", "A paragraph.", "- one\n- two", "```\ncode\n```"])
    }

    @Test func `the blank lines after a block and its last line ending are not part of it`() {
        #expect(texts(of: parse("a\n\n\n\nb\n\n")) == ["a", "b"])
        #expect(
            texts(of: parse("    code  \n\n\n")) == ["    code  "],
            "trailing white space on the last line is a code line's content"
        )
        #expect(texts(of: parse("a\r\n\r\nb\r\n")) == ["a", "b"])
        #expect(texts(of: parse("a\rb\r\rc")) == ["a\rb", "c"])
    }

    @Test func `a closing fence is inside its block, and an unclosed fence runs to the end of the input`() {
        #expect(texts(of: parse("```swift\nlet a = 1\n```\nafter\n")) == ["```swift\nlet a = 1\n```", "after"])
        #expect(
            texts(of: parse("```\ncode\n\n")) == ["```\ncode\n\n"],
            "the blank lines after an unclosed fence are lines of its code"
        )
        #expect(
            texts(of: parse("<!--\nx\n\n\n")) == ["<!--\nx\n\n\n"],
            "and of an HTML block whose end condition never came"
        )
        #expect(
            texts(of: parse("<div>\nx\n\ny\n")) == ["<div>\nx", "y"],
            "an HTML block of condition 6 ends at a blank line"
        )
        #expect(
            texts(of: parse("```\n```\n")) == ["```\n```"],
            "an empty fence has no leaf to name it, and has a range all the same"
        )
    }

    @Test func `lines a block took by lazy continuation and its markers are inside it`() {
        #expect(texts(of: parse("> a\nb\n\nc")) == ["> a\nb", "c"])
        #expect(texts(of: parse("  - a\n    b\n- c\n")) == ["  - a\n    b\n- c"])
        #expect(texts(of: parse("Title\n=====\nbody\n")) == ["Title\n=====", "body"])
    }

    @Test func `a paragraph made only of link reference definitions has left the tape and has no entry`() {
        let document = parse("[a]: /url\n[b]: /other\n\ntext\n")
        #expect(document.blockCount == 1)
        #expect(texts(of: document) == ["text"])
    }

    @Test func `an indented code block ends before the blank lines after it`() {
        #expect(texts(of: parse("    code\n\n\nafter")) == ["    code", "after"])
    }

    @Test
    func
        `every example of the specifications: the entries name the blocks the tape lists, in order, inside the source and apart`()
    {
        for example in SpecConformanceTests.examples {
            let document = parse(example.markdown, extensions: example.file == "commonmark" ? [] : .gfm)
            let blocks = Array(document.topLevelBlocks)
            #expect(blocks.count == document.blockCount, "\(example.id)")
            var previousEnd = 0
            for (ordinal, block) in blocks.enumerated() {
                #expect(block.ordinal == ordinal, "\(example.id)")
                #expect(
                    block.sourceRange.lowerBound >= previousEnd,
                    "\(example.id) block \(ordinal) overlaps the one before"
                )
                #expect(block.sourceRange.upperBound <= document.source.count, "\(example.id)")
                #expect(!block.sourceRange.isEmpty, "\(example.id) block \(ordinal) has no source")
                previousEnd = block.sourceRange.upperBound
            }
        }
    }

    @Test func `every example of the specifications: a block's own bytes parse to the same block structure`() {
        for example in SpecConformanceTests.examples {
            let extensions: MarkdownExtensions = example.file == "commonmark" ? [] : .github
            let document = parse(example.markdown, extensions: extensions)
            for block in document.topLevelBlocks {
                let alone = MarkdownParser.parse(Array(document.source[block.sourceRange]), extensions: extensions)
                let aloneBlocks = Array(alone.topLevelBlocks)
                #expect(
                    aloneBlocks.count == 1,
                    "\(example.id): `\(texts(of: document))` alone is \(aloneBlocks.count) blocks"
                )
                if let first = aloneBlocks.first {
                    #expect(structure(alone, first) == structure(document, block), "\(example.id)")
                    // A reference lookup is part of the hash (ReferenceStampTests); a document that made none has the hash of its bytes alone.
                    if document.stamps.count == 0 { #expect(first.contentHash == block.contentHash, "\(example.id)") }
                }
            }
        }
    }

    @Test
    func `equal blocks have equal hashes wherever they stand, and a different byte or kind makes a different one`() {
        let document = parse("same\n\nother\n\n- list\n\nsame\n")
        let hashes = document.topLevelBlocks.map(\.contentHash)
        #expect(hashes[0] == hashes[3])
        #expect(Set(hashes).count == 3)
        let kinds = parse("# a\n\na\n").topLevelBlocks.map(\.contentHash)
        #expect(kinds[0] != kinds[1], "`# a` and `a` are different blocks whatever their text")
        #expect(
            Array(parse("a\n").topLevelBlocks).map(\.contentHash)
                == Array(parse("\n\na\n\n\n").topLevelBlocks).map(\.contentHash),
            "blank lines are not the block"
        )
    }

    @Test func `streamed one byte at a time, the entries are those of the whole document`() {
        for example in SpecConformanceTests.examples {
            let extensions: MarkdownExtensions = example.file == "commonmark" ? [] : .github
            let bytes = Array(example.markdown.utf8)
            let whole = MarkdownParser.parse(bytes, extensions: extensions)
            var parser = MarkdownParser(extensions: extensions)
            for byte in bytes { parser.append([byte]) }
            parser.finish()
            let streamed = parser.snapshot()
            let expected = whole.topLevelBlocks.map {
                [$0.sourceRange.lowerBound, $0.sourceRange.upperBound, Int(truncatingIfNeeded: $0.contentHash)]
            }
            let found = streamed.topLevelBlocks.map {
                [$0.sourceRange.lowerBound, $0.sourceRange.upperBound, Int(truncatingIfNeeded: $0.contentHash)]
            }
            #expect(found == expected, "\(example.id)")
        }
    }

    @Test func `a block that was final keeps its range and hash in every later snapshot`() {
        for example in SpecConformanceTests.examples {
            let extensions: MarkdownExtensions = example.file == "commonmark" ? [] : .github
            var parser = MarkdownParser(extensions: extensions)
            var seen: [Int: [Int]] = [:]
            for byte in example.markdown.utf8 {
                parser.append([byte])
                for block in parser.snapshot().topLevelBlocks where block.isFinal {
                    let entry = [
                        block.sourceRange.lowerBound, block.sourceRange.upperBound,
                        Int(truncatingIfNeeded: block.contentHash)
                    ]
                    if let before = seen[block.ordinal] {
                        #expect(before == entry, "\(example.id) block \(block.ordinal) changed after it was final")
                    }
                    seen[block.ordinal] = entry
                }
            }
        }
    }

    @Test func `a walk can start at any block, and a block is found by its ordinal or by a byte`() {
        let document = parse("# one\n\ntwo\n\n- three\n\nfour\n")
        let all = Array(document.topLevelBlocks)
        for start in 0 ... all.count {
            #expect(Array(document.blocks(from: start)).map(\.ordinal) == Array(start ..< all.count))
        }
        #expect(document.block(at: 2) == all[2])
        #expect(document.block(at: -1) == nil && document.block(at: 4) == nil)
        #expect(document.blockOrdinal(containing: 0) == 0)
        #expect(document.blockOrdinal(containing: all[2].sourceRange.lowerBound + 1) == 2)
        #expect(
            document.blockOrdinal(containing: all[1].sourceRange.upperBound) == 1,
            "a byte between blocks belongs to the one before"
        )
        #expect(MarkdownParser.parse([]).blockOrdinal(containing: 0) == nil)
    }
}
