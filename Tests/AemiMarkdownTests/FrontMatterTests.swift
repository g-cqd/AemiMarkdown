import AemiFrontMatter
import AemiHMMMLCore
import AemiTOML
import AemiTestKit
import AemiYAML
import Testing

@testable import AemiMarkdown

/// `MarkdownExtensions.frontMatter` (ADR-0006): the head is one block, the body reads as it would alone, and without a head nothing
/// changes; streaming and editing give what a whole parse gives.
@Suite("Front matter")
struct FrontMatterBlockTests {
    static let on: MarkdownExtensions = [.github, .frontMatter]

    static let texts: [String] = [
        "---\ntitle: Notes\ntags: [a, b]\n---\n# Body\n\ntext\n",
        "+++\ntitle = \"x\"\n[params]\nn = 1\n+++\npara\n",
        "{\"title\": \"x\",\n \"n\": [1, 2]}\n# H\n",
        "---\n---\n",
        "---\ntitle: x\n---",
        "\u{FEFF}---\r\na: 1\r\n---\r\nbody\r\n",
        "---\ra: 1\r...\rbody",
        "---\ntitle: x\n\nno closing, so Markdown\n",
        "---\n",
        "----\nx\n----\n",
        "{{< shortcode >}}\n",
        "{\"a\": 1} text after the object\n",
        "text\n---\nmore\n---\n",
        "---\na: |\n  ---\n---\n> quote\n- item\n",
        "---\ndescription: Use this: when\n---\nbody [link]\n\n[link]: /url\n"
    ]

    static func parse(_ text: String, _ extensions: MarkdownExtensions = on) -> MarkdownDocument {
        MarkdownParser.parse(Array(text.utf8), extensions: extensions)
    }

    @Test("the head is the first block, its lines as written, and readable")
    func head() throws {
        let document = Self.parse(Self.texts[0])
        let head = try #require(document.frontMatter)
        #expect(head.format == .yaml)
        let first = try #require(Array(document.topLevelBlocks).first)
        #expect(first.node.kind == .frontMatter)
        #expect(first.sourceRange == 0 ..< 33)
        #expect(
            EditOracle.signature(document, first) == [
                "enter frontMatter 1", "leaf codeLine 0 0 title: Notes", "leaf codeLine 0 0 tags: [a, b]",
                "exit frontMatter"
            ]
        )
        let value = try #require(document.readFrontMatter()?.value?.yaml)
        #expect(value.root["title"]?.string == "Notes")
        #expect(value.root["tags"]?.count == 2)
    }

    @Test("TOML and JSON heads are blocks too, with their formats")
    func formats() throws {
        #expect(Self.parse(Self.texts[1]).frontMatter?.format == .toml)
        #expect(Self.parse(Self.texts[1]).readFrontMatter()?.value?.toml?.root["params"]?["n"]?.integer == 1)
        let json = Self.parse(Self.texts[2])
        #expect(json.frontMatter?.format == .json)
        #expect(Array(json.topLevelBlocks).first?.node.payload == 3)
    }

    @Test("a head's errors are diagnostics, never a failure, with offsets in the document")
    func recovering() throws {
        let document = Self.parse(Self.texts[14])
        let reading = try #require(document.readFrontMatter())
        #expect(reading.value?.yaml?.root["description"]?.string == "Use this: when")
        let colon = try #require(reading.diagnostics.recorded.first?.range.lowerBound)
        #expect(document.source[colon] == UInt8(ascii: ":"))
        // The body reads on: a paragraph with its link, the definition taken by it.
        #expect(Array(document.topLevelBlocks).count == 2)
    }

    @Test("the body reads as it would alone; without a head, or with the extension off, the text reads as before")
    func body() {
        for text in Self.texts {
            let document = Self.parse(text)
            let off = Self.parse(text, .github)
            if let head = document.frontMatter {
                let body = Array(document.source[head.bodyStart...])
                let alone = MarkdownParser.parse(body, extensions: .github)
                #expect(
                    Array(EditOracle.signatures(document).dropFirst()) == EditOracle.signatures(alone),
                    "\(text.debugDescription)"
                )
            } else {
                #expect(EditOracle.signatures(document) == EditOracle.signatures(off), "\(text.debugDescription)")
                #expect(document.blockSlotCount == off.blockSlotCount)
            }
            #expect(TapeValidator.problem(in: document) == nil, "\(text.debugDescription)")
        }
    }

    @Test("a head past the bound is Markdown")
    func bound() {
        let limits = MarkdownLimits(maxFrontMatterBytes: 8)
        let document = MarkdownParser.parse(Array(Self.texts[0].utf8), extensions: Self.on, limits: limits)
        #expect(document.frontMatter == nil)
        #expect(EditOracle.signatures(document) == EditOracle.signatures(Self.parse(Self.texts[0], .github)))
    }

    @Test("streamed in pieces, with a snapshot after each, the document is the whole parse", arguments: [1, 2, 3, 7])
    func streaming(size: Int) {
        // A definition after its link does not reach it while streaming (MarkdownParser.snapshot()): those texts are left out, as
        // StreamingTests leaves them out.
        for text in Self.texts where !text.contains("]:") {
            let bytes = Array(text.utf8)
            var parser = MarkdownParser(extensions: Self.on)
            var start = 0
            while start < bytes.count {
                let end = min(bytes.count, start + size)
                parser.append(Array(bytes[start ..< end]))
                let snapshot = parser.snapshot()
                #expect(TapeValidator.problem(in: snapshot) == nil, "\(text.debugDescription) at \(end)")
                start = end
            }
            parser.finish()
            let whole = MarkdownParser.parse(bytes, extensions: Self.on)
            let streamed = parser.document()
            #expect(EditOracle.signatures(streamed) == EditOracle.signatures(whole), "\(text.debugDescription)")
            #expect(streamed.frontMatter == whole.frontMatter)
            #expect(parser.blocks.committedSlots == MarkdownParser.parsed(bytes, Self.on).blocks.committedSlots)
        }
    }

    @Test("every one-byte edit of every text gives the whole parse, and a change that tells the truth")
    func edits() {
        let insertions: [[UInt8]] = [[], Array("x".utf8), Array("\n".utf8), Array("---\n".utf8), Array("-".utf8)]
        for text in Self.texts {
            let bytes = Array(text.utf8)
            for offset in 0 ... bytes.count {
                for inserted in insertions {
                    let upper = inserted.isEmpty ? min(offset + 1, bytes.count) : offset
                    var editor = MarkdownEditor(bytes, extensions: Self.on)
                    let old = editor.document
                    let change = editor.replace(offset ..< upper, with: inserted)
                    let problems = EditOracle.problems(old: old, editor: editor, change: change, extensions: Self.on)
                    #expect(problems.isEmpty, "\(text.debugDescription) at \(offset) with \(inserted): \(problems)")
                    #expect(
                        editor.document.frontMatter
                            == MarkdownParser.parse(Array(editor.document.source), extensions: Self.on).frontMatter
                    )
                }
            }
        }
    }
}

extension FrontMatterBlockTests {
    @Test("random documents from the fences' alphabet: valid tapes, streamed as parsed whole, edited as parsed whole")
    func random() {
        var generator = SeededRNG(seed: 0x464D_4D44)
        let alphabet = Array("---+++...{}\"\\: \t\n\n\r#a1[]".utf8)
        for _ in 0 ..< 400 {
            let bytes = (0 ..< Int.random(in: 0 ... 40, using: &generator))
                .map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)] }
            let whole = MarkdownParser.parse(bytes, extensions: Self.on)
            #expect(TapeValidator.problem(in: whole) == nil)
            var parser = MarkdownParser(extensions: Self.on)
            for byte in bytes {
                parser.append([byte])
                _ = parser.snapshot()
            }
            parser.finish()
            if !bytes.contains(UInt8(ascii: "]")) {
                #expect(EditOracle.signatures(parser.document()) == EditOracle.signatures(whole), "\(bytes)")
            }
            guard !bytes.isEmpty else { continue }
            let offset = Int.random(in: 0 ..< bytes.count, using: &generator)
            let inserted = [alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)]]
            var editor = MarkdownEditor(bytes, extensions: Self.on)
            let old = editor.document
            let change = editor.replace(offset ..< offset + Int.random(in: 0 ... 1, using: &generator), with: inserted)
            let problems = EditOracle.problems(old: old, editor: editor, change: change, extensions: Self.on)
            #expect(problems.isEmpty, "\(bytes) at \(offset): \(problems)")
        }
    }
}

extension MarkdownParser {
    /// A finished parser, for its tapes.
    static func parsed(_ bytes: [UInt8], _ extensions: MarkdownExtensions) -> MarkdownParser {
        var parser = MarkdownParser(extensions: extensions)
        parser.append(bytes)
        parser.finish()
        return parser
    }
}
