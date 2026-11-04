import Testing

@testable import AemiMarkdown

/// The differential test of ADR-0003: whatever the edit, the edited document is a fresh parse of the edited source, and the change names exactly the blocks that
/// differ. Every specification example, every position, every kind of edit; then a large document at the positions that matter; then random edits.
@Suite("An edit is a fresh parse, and the change says the truth about it")
struct EditDifferentialTests {
    private static let insertions: [[UInt8]] = [
        "x", "\n", "\n\n", "#", "> ", "- ", "`", "```\n", "    ", "[", "]: /u\n", "|", "\t"
    ]
    .map { Array($0.utf8) }

    private func run(_ source: [UInt8], _ range: Range<Int>, _ bytes: [UInt8], extensions: MarkdownExtensions)
        -> [String]
    {
        var editor = MarkdownEditor(source, extensions: extensions)
        let old = editor.document
        let change = editor.replace(range, with: bytes)
        return EditOracle.problems(old: old, editor: editor, change: change, extensions: extensions)
    }

    @Test func `every example of the specifications, every position, insert, delete and replace`() {
        var failures = 0
        var checked = 0
        for example in SpecConformanceTests.examples {
            let extensions: MarkdownExtensions = example.file == "commonmark" ? [] : .github
            let source = Array(example.markdown.utf8)
            for position in 0 ... source.count {
                for bytes in Self.insertions {
                    checked += 1
                    let found = run(source, position ..< position, bytes, extensions: extensions)
                    if !found.isEmpty, failures < 5 {
                        failures += 1
                        Issue.record("example \(example.id): insert \(bytes) at \(position): \(found)")
                    }
                }
                guard position < source.count else { continue }
                for bytes in [[], [UInt8(ascii: "\n")], [UInt8(ascii: "x")]] as [[UInt8]] {
                    checked += 1
                    let found = run(source, position ..< (position + 1), bytes, extensions: extensions)
                    if !found.isEmpty, failures < 5 {
                        failures += 1
                        Issue.record("example \(example.id): replace \(position) by \(bytes): \(found)")
                    }
                }
            }
        }
        #expect(checked > 100_000)
    }

    /// A document of many kinds of block, `repeats` times over.
    private static func document(repeats: Int) -> [UInt8] {
        let unit =
            "# Heading\n\nA paragraph with *emphasis*, `code` and a [link][ref].\n\n- one\n- two\n  - nested\n\n> quote\n> more\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n1. first\n2. second\n\n---\n\n<div>\nhtml\n</div>\n\n"
        return Array((String(repeating: unit, count: repeats) + "[ref]: /target \"title\"\n").utf8)
    }

    @Test func `a large document at the positions that matter, with the edits that matter`() {
        let source = Self.document(repeats: 60)
        let blocks = Array(MarkdownParser.parse(source).topLevelBlocks)
        let count = source.count
        func block(_ ordinal: Int) -> Range<Int> { blocks[ordinal].sourceRange }
        let fence = blocks.first { $0.node.kind == .codeBlock }!.sourceRange
        let table = blocks.first { $0.node.kind == .table }!.sourceRange
        let list = blocks.first { $0.node.kind == .list }!.sourceRange
        let positions = [
            0, block(0).upperBound, block(1).lowerBound, count / 4, count / 2, count * 3 / 4,
            block(blocks.count - 1).lowerBound, count - 1, count,
            fence.lowerBound + 3, (fence.lowerBound + fence.upperBound) / 2, fence.upperBound - 1, table.lowerBound + 4,
            table.upperBound - 2, list.lowerBound + 3
        ]
        let big = [UInt8](repeating: UInt8(ascii: "w"), count: 10_000)
        for position in positions {
            for bytes in Self.insertions + [big, Array("\n\n# new\n\n".utf8)] {
                #expect(
                    run(source, position ..< position, bytes, extensions: .github).isEmpty,
                    "insert \(bytes.count) bytes at \(position)"
                )
            }
            for length in [1, 7, 300] where position + length <= count {
                #expect(
                    run(source, position ..< (position + length), [], extensions: .github).isEmpty,
                    "delete \(length) at \(position)"
                )
                #expect(
                    run(source, position ..< (position + length), Array("replaced\n\n".utf8), extensions: .github)
                        .isEmpty,
                    "replace \(length) at \(position)"
                )
            }
        }
        for ordinal in [0, 1, blocks.count / 2, blocks.count - 1] {
            #expect(run(source, block(ordinal), [], extensions: .github).isEmpty, "cut block \(ordinal)")
        }
        #expect(run(source, 0 ..< 0, source, extensions: .github).isEmpty, "paste the document on itself at the start")
    }

    @Test(
        arguments: [
            0x9E37_79B9_7F4A_7C15, 0x1234_5678_9ABC_DEF1, 0xDEAD_BEEF_CAFE_F00D, 0x0F0F_0F0F_1234_5677,
            0x7777_1111_3333_5555, 0x2545_F491_4F6C_DD1D
        ] as [UInt64]
    )
    func `random edits of random length on a document of every kind`(seed: UInt64) {
        var state = seed
        func next() -> Int {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Int(truncatingIfNeeded: state >> 1)
        }
        var source = Self.document(repeats: 3)
        let alphabet = Array("ab *_`[]()<>#-+=|~\n\n\t0123.!\\&:^$".utf8)
        var editor = MarkdownEditor(source)
        var whole = 0
        for step in 0 ..< 2500 {
            let start = next() % (source.count + 1)
            let length = next() % 4 == 0 ? next() % 40 : next() % 3
            let end = min(source.count, start + length)
            let inserted = (0 ..< next() % 12).map { _ in alphabet[next() % alphabet.count] }
            let old = editor.document
            let change = editor.replace(start ..< end, with: inserted)
            if editor.lastEditParsedWhole { whole += 1 }
            source.replaceSubrange(start ..< end, with: inserted)
            let found = EditOracle.problems(old: old, editor: editor, change: change, extensions: .github)
            #expect(found.isEmpty, "seed \(seed) step \(step) (\(start)..<\(end)): \(found)")
            #expect(Array(editor.document.source) == source)
            if !found.isEmpty { break }
        }
        #expect(whole > 0 && whole < 1500, "both ways of editing run: \(whole) of 2500 parsed whole")
    }
}
