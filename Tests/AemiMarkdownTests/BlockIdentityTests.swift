import Testing

@testable import AemiMarkdown

/// A renderer caches each top-level block by identity and lays out again only the block that is not final (ADR-0001, decision 3).
@Suite("Top-level blocks have stable identities and say when they are final")
struct BlockIdentityTests {
    private func blocks(_ document: MarkdownDocument) -> [MarkdownBlock] { Array(document.topLevelBlocks) }

    private func events(_ document: MarkdownDocument, _ block: MarkdownBlock) -> [MarkdownEvent] {
        Array(document.events(of: block))
    }

    @Test func `a whole document's top-level blocks are listed in order, all final`() {
        let document = MarkdownParser.parse(Array("# Title\n\nA paragraph.\n\n- one\n- two\n\n```\ncode\n```\n".utf8))
        let kinds = blocks(document).map(\.node.kind)
        #expect(kinds == [.heading, .paragraph, .list, .codeBlock])
        #expect(blocks(document).allSatisfy { $0.isFinal })
        #expect(Set(blocks(document).map(\.id)).count == 4)
    }

    @Test func `walking every block in turn is walking the document`() {
        for example in SpecConformanceTests.examples {
            let document = MarkdownParser.parse(
                Array(example.markdown.utf8), extensions: example.file == "commonmark" ? [] : .gfm)
            let joined = blocks(document).flatMap { events(document, $0) }
            #expect(joined == Array(document.events), "\(example.id)")
        }
    }

    @Test func `while streaming, the open block is not final, and an empty document has no blocks`() {
        var parser = MarkdownParser()
        #expect(blocks(parser.snapshot()).isEmpty)
        parser.append(Array("# Title\n\nStill being written".utf8))
        let open = blocks(parser.snapshot())
        #expect(open.map(\.node.kind) == [.heading, .paragraph])
        #expect(open.map(\.isFinal) == [true, false])
        parser.append(Array(" and done.\n\n".utf8))
        #expect(blocks(parser.snapshot()).map(\.isFinal) == [true, true], "a blank line closed it and nothing is open")
    }

    @Test func `a list is final once a complete line has closed it, though the tape has not committed it yet`() {
        var parser = MarkdownParser()
        parser.append(Array("- one\n- two\n\nafter".utf8))
        let partial = blocks(parser.snapshot()).map(\.isFinal)
        #expect(partial == [false, false], "`after` has not ended: it could still be `- three`")
        parser.append(Array(" this\n".utf8))
        let shown = blocks(parser.snapshot())
        #expect(shown.map(\.node.kind) == [.list, .paragraph])
        #expect(shown.map(\.isFinal) == [true, false])
    }

    /// The property a renderer relies on: a block once reported final comes back with the same identity and the same content in every later
    /// snapshot and in the finished document. Every spec example, streamed one byte at a time.
    @Test func `a block reported final never changes again`() {
        for example in StreamingTests.examples {
            let bytes = Array(example.markdown.utf8)
            var parser = MarkdownParser(extensions: example.file == "commonmark" ? [] : .gfm)
            var final: [Int: [MarkdownEvent]] = [:]
            for byte in bytes {
                parser.append([byte])
                let snapshot = parser.snapshot()
                for block in blocks(snapshot) {
                    let walked = events(snapshot, block)
                    if let earlier = final[block.id] {
                        #expect(
                            walked == earlier && block.isFinal,
                            "\(example.id): block \(block.id) changed after it was final")
                    } else if block.isFinal {
                        final[block.id] = walked
                    }
                }
            }
            parser.finish()
            let finished = parser.snapshot()
            let ids = Dictionary(uniqueKeysWithValues: blocks(finished).map { ($0.id, events(finished, $0)) })
            for (id, walked) in final {
                #expect(ids[id] == walked, "\(example.id): block \(id) differs in the finished document")
            }
        }
    }

    @Test func `a streamed document's identities are those of the same document parsed whole`() {
        for example in StreamingTests.examples {
            let bytes = Array(example.markdown.utf8)
            let extensions: MarkdownExtensions = example.file == "commonmark" ? [] : .gfm
            var parser = MarkdownParser(extensions: extensions)
            for piece in stride(from: 0, to: bytes.count, by: 5) {
                parser.append(Array(bytes[piece ..< Swift.min(piece + 5, bytes.count)]))
            }
            parser.finish()
            let streamed = blocks(parser.snapshot()).map(\.id)
            #expect(streamed == blocks(MarkdownParser.parse(bytes, extensions: extensions)).map(\.id), "\(example.id)")
        }
    }
}
