import Testing

@testable import AemiMarkdown

/// A block's content hash says what its reference links resolved to, not only which bytes it holds (ADR-0003).
@Suite("The content hash follows the definitions that the block's links use")
struct ReferenceStampTests {
    private func hashes(_ markdown: String) -> [UInt64] {
        MarkdownParser.parse(Array(markdown.utf8)).topLevelBlocks.map(\.contentHash)
    }

    @Test func `the same block with another destination behind its label has another hash`() {
        let one = hashes("see [a]\n\n[a]: /one\n")
        let two = hashes("see [a]\n\n[a]: /two\n")
        #expect(one.count == 1 && two.count == 1 && one != two)
    }

    @Test func `a title that changes changes the hash`() {
        #expect(hashes("[a]\n\n[a]: /x \"one\"\n") != hashes("[a]\n\n[a]: /x \"two\"\n"))
    }

    @Test func `a label that was unresolved and now resolves has another hash`() {
        #expect(hashes("see [a]\n") != hashes("see [a]\n\n[a]: /x\n"))
    }

    @Test func `a label that resolves to the same definition has the same hash wherever the definition stands`() {
        #expect(hashes("see [a]\n\n[a]: /x\n") == hashes("[a]: /x\n\nsee [a]\n"))
        #expect(hashes("see [A]\n\n[a]: /x\n") != hashes("see [b]\n\n[a]: /x\n"), "another label")
    }

    @Test func `a block that uses no reference keeps its hash whatever the definitions are`() {
        let plain = hashes("plain text\n")
        #expect(hashes("plain text\n\n[a]: /x\n") == plain)
        #expect(hashes("[a]: /x\n\nplain text\n") == plain)
    }

    @Test func `a block that is not a link keeps its hash, and a definition elsewhere does not move it`() {
        let before = hashes("one\n\n[a] x\n\ntwo\n")
        let after = hashes("one\n\n[a] x\n\ntwo\n\n[b]: /y\n")
        #expect(before[0] == after[0] && before[2] == after[2])
    }

    @Test func `a footnote that exists changes the block that cites it`() {
        #expect(hashes("text[^1]\n") != hashes("text[^1]\n\n[^1]: note\n"))
    }

    @Test func `a reference inside a list item or a table cell counts for the top-level block`() {
        #expect(hashes("- item [a]\n\n[a]: /one\n") != hashes("- item [a]\n\n[a]: /two\n"))
        #expect(hashes("| h |\n|---|\n| [a] |\n\n[a]: /one\n") != hashes("| h |\n|---|\n| [a] |\n\n[a]: /two\n"))
    }

    @Test func `blocks walked from an ordinal have the hashes of the walk from the start`() {
        let document = MarkdownParser.parse(
            Array("[a]: /x\n\none [a]\n\ntwo\n\nthree [a]\n\n- four [b]\n\n[b]: /y\n".utf8)
        )
        let all = Array(document.topLevelBlocks)
        for ordinal in all.indices {
            let from = Array(document.blocks(from: ordinal))
            #expect(from.map(\.contentHash) == all[ordinal...].map(\.contentHash), "from \(ordinal)")
        }
    }

    @Test func `a streamed document has the hashes of the document parsed whole when its definitions come first`() {
        let text = "[a]: /x \"t\"\n\none [a] and [b]\n\n> quote [a]\n\n```\n[a]\n```\n"
        var parser = MarkdownParser()
        for byte in text.utf8 { parser.append([byte]) }
        parser.finish()
        #expect(parser.snapshot().topLevelBlocks.map(\.contentHash) == hashes(text))
    }
}

/// A last line of 512 bytes or more with no line ending is read incrementally while it grows; that reading used to know no definitions.
@Suite("A long last line resolves the definitions before it")
struct LongLastLineReferenceTests {
    @Test(arguments: ["", "\n"])
    func `reference links in a long last line resolve whether or not a line ending follows`(ending: String) {
        let filler = String(repeating: "word ", count: 130)
        let text = "[ref]: /url \"t\"\n\nSee [ref] and [ref][] and [x][ref] then " + filler + ending
        var links = 0
        for event in MarkdownParser.parse(Array(text.utf8)).events {
            if case .enter(let node) = event, node.kind == .link { links += 1 }
        }
        #expect(links == 3)
    }

    @Test func `a streamed document resolves them too, and its hash is the one of the whole`() {
        let filler = String(repeating: "word ", count: 130)
        let text = "[ref]: /url\n\nSee [ref] then " + filler
        var parser = MarkdownParser()
        for start in stride(from: 0, to: text.utf8.count, by: 97) {
            parser.append(Array(text.utf8.dropFirst(start).prefix(97)))
        }
        parser.finish()
        let whole = MarkdownParser.parse(Array(text.utf8))
        #expect(parser.snapshot().topLevelBlocks.map(\.contentHash) == whole.topLevelBlocks.map(\.contentHash))
    }
}
