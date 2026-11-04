import Testing

@testable import AemiMarkdown

/// An edit anywhere tells which blocks differ (ADR-0003, ask roadmap 0203, phase A).
@Suite("The editor replaces bytes anywhere and names the blocks that differ")
struct MarkdownEditorTests {
    private func editor(_ text: String) -> MarkdownEditor { MarkdownEditor(Array(text.utf8)) }

    private func edit(_ editor: inout MarkdownEditor, _ range: Range<Int>, _ text: String) -> MarkdownChange {
        editor.replace(range, with: Array(text.utf8))
    }

    private func text(_ editor: MarkdownEditor) -> String { String(decoding: editor.document.source, as: UTF8.self) }

    @Test func `a word changed in one paragraph is one block`() {
        var editor = editor("# Title\n\nfirst\n\nsecond\n\nthird\n")
        let change = edit(&editor, 16 ..< 22, "2nd")
        #expect(text(editor) == "# Title\n\nfirst\n\n2nd\n\nthird\n")
        #expect(
            change
                == MarkdownChange(
                    replaced: 16 ..< 22,
                    insertedBytes: 3,
                    firstBlock: 2,
                    removedBlocks: 1,
                    insertedBlocks: 1
                )
        )
        #expect(change.changedBlocks == 2 ..< 3 && change.byteShift == -3 && change.blockShift == 0)
    }

    @Test func `white space between blocks changes no block`() {
        var editor = editor("one\n\ntwo\n")
        let change = edit(&editor, 4 ..< 4, "\n\n")
        #expect(change.isEmpty && change.byteShift == 2)
        #expect(editor.document.topLevelBlocks.map(\.sourceRange) == [0 ..< 3, 7 ..< 10])
    }

    @Test func `a paragraph inserted at the start moves every block and changes one`() {
        var editor = editor("one\n\ntwo\n")
        let change = edit(&editor, 0 ..< 0, "zero\n\n")
        #expect(
            change
                == MarkdownChange(
                    replaced: 0 ..< 0,
                    insertedBytes: 6,
                    firstBlock: 0,
                    removedBlocks: 0,
                    insertedBlocks: 1
                )
        )
        #expect(change.newOrdinal(ofOld: 0) == 1 && change.newOrdinal(ofOld: 1) == 2)
    }

    @Test func `a paragraph appended at the end is the last block`() {
        var editor = editor("one\n\ntwo\n")
        let change = edit(&editor, 9 ..< 9, "\nthree\n")
        #expect(change.firstBlock == 2 && change.removedBlocks == 0 && change.insertedBlocks == 1)
    }

    @Test func `joining two paragraphs removes two blocks and adds one`() {
        var editor = editor("one\n\ntwo\n\nthree\n")
        let change = edit(&editor, 3 ..< 5, " ")
        #expect(text(editor) == "one two\n\nthree\n")
        #expect(
            change.firstBlock == 0 && change.removedBlocks == 2 && change.insertedBlocks == 1 && change.blockShift == -1
        )
        #expect(change.newOrdinal(ofOld: 1) == 0 && change.newOrdinal(ofOld: 2) == 1)
    }

    @Test func `splitting a paragraph adds a block`() {
        var editor = editor("one two\n\nthree\n")
        let change = edit(&editor, 3 ..< 4, "\n\n")
        #expect(change.removedBlocks == 1 && change.insertedBlocks == 2)
    }

    @Test func `opening a fence changes everything after it, and closing it restores them`() {
        var editor = editor("a\n\nb\n\nc\n")
        let opened = edit(&editor, 3 ..< 3, "```\n")
        #expect(opened.firstBlock == 1 && opened.removedBlocks == 2 && opened.insertedBlocks == 1)
        let closed = edit(&editor, 3 ..< 7, "")
        #expect(closed.firstBlock == 1 && closed.removedBlocks == 1 && closed.insertedBlocks == 2)
    }

    @Test func `a definition added below changes the block above that uses it`() {
        var editor = editor("see [a]\n\nother\n")
        let change = edit(&editor, 15 ..< 15, "\n[a]: /x\n")
        #expect(change.firstBlock == 0 && change.removedBlocks == 1 && change.insertedBlocks == 1)
    }

    @Test func `an edit outside the source is cut to it and an empty document can be filled and emptied`() {
        var editor = editor("")
        #expect(editor.document.blockCount == 0)
        let filled = edit(&editor, -5 ..< 99, "# hi\n")
        #expect(text(editor) == "# hi\n" && filled.replaced == 0 ..< 0 && filled.insertedBlocks == 1)
        let emptied = edit(&editor, 0 ..< 5, "")
        #expect(text(editor).isEmpty && emptied.removedBlocks == 1 && emptied.insertedBlocks == 0)
    }

    @Test func `offsets map through the edit`() {
        let change = MarkdownChange(
            replaced: 10 ..< 20,
            insertedBytes: 4,
            firstBlock: 0,
            removedBlocks: 0,
            insertedBlocks: 0
        )
        #expect(
            change.newOffset(ofOld: 5) == 5 && change.newOffset(ofOld: 10) == 10 && change.newOffset(ofOld: 15) == 10
        )
        #expect(change.newOffset(ofOld: 20) == 14 && change.newOffset(ofOld: 100) == 94)
    }

    @Test func `typing a document one byte at a time gives the document parsed whole`() {
        let markdown =
            "# T\n\nsome *text* with [a link][x]\n\n- one\n- two\n\n```sh\nls\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n[x]: /y\n"
        var editor = editor("")
        for byte in markdown.utf8 {
            editor.replace(editor.document.source.count ..< editor.document.source.count, with: [byte])
        }
        let whole = MarkdownParser.parse(Array(markdown.utf8))
        #expect(editor.document.topLevelBlocks.map(\.contentHash) == whole.topLevelBlocks.map(\.contentHash))
        #expect(EditOracle.signatures(editor.document) == EditOracle.signatures(whole))
    }

    @Test func `an edit inside a paragraph reads its own region, and one that changes a definition parses the whole`() {
        var editor = editor("# T\n\nsee [a]\n\n- one\n- two\n\n[a]: /x\n\nlast\n")
        _ = edit(&editor, 8 ..< 8, "x")
        #expect(!editor.lastEditParsedWhole)
        _ = edit(&editor, 25 ..< 25, "y")
        #expect(editor.lastEditParsedWhole, "the definition moved")
        _ = edit(&editor, 0 ..< 0, "z")
        #expect(!editor.lastEditParsedWhole, "a definition after the edit only moves")
    }

    @Test func `a document with a diagnostic is edited by the whole parse, and the diagnostic goes when its byte does`()
    {
        var editor = editor("a\u{0}b\n\ntext\n")
        #expect(editor.document.diagnostics.contains(.controlBytes))
        _ = edit(&editor, 6 ..< 6, "x")
        #expect(editor.lastEditParsedWhole)
        _ = edit(&editor, 1 ..< 2, "")
        #expect(!editor.document.diagnostics.contains(.controlBytes))
    }

    @Test func `a link to a definition after the edit still names the definition when the edit moves it`() {
        var editor = editor("see [a]\n\nmore\n\n[a]: /target\n")
        _ = edit(&editor, 0 ..< 0, "0123456789\n\n")
        #expect(!editor.lastEditParsedWhole)
        var destinations: [String] = []
        for event in editor.document.events {
            if case .leaf(let node) = event, node.kind == .linkDestination {
                destinations.append(String(decoding: editor.document.source[node.range], as: UTF8.self))
            }
        }
        #expect(destinations == ["/target"])
    }

    @Test func `an edit in the middle of a large document reads a few blocks, wherever it is`() {
        let paragraph = "A paragraph with *emphasis*, `code` and a [link](https://example.com/page) in it.\n\n"
        let source = Array(String(repeating: paragraph, count: 5000).utf8)
        var editor = MarkdownEditor(source)
        for fraction in [0.0, 0.25, 0.5, 0.75, 0.999] {
            let position = Int(Double(source.count) * fraction) + 3
            _ = editor.replace(position ..< position, with: Array("word ".utf8))
            _ = editor.replace(position ..< (position + 5), with: [])
            #expect(!editor.lastEditParsedWhole)
            // The region the last edit read: a block or two, not the document (5000 blocks, about 60,000 slots).
            #expect(
                editor.region.blocks.count < 40 && editor.region.inlines.count < 100,
                "at \(fraction): \(editor.region.blocks.count) block slots read"
            )
        }
        #expect(Array(editor.document.source) == source)
    }
}
