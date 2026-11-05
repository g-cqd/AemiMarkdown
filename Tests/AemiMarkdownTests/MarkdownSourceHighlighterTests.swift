import Testing

@testable import AemiMarkdown

/// Markdown source coloured while it is typed (ask roadmap 0085 and 0151, made neutral): colour only, markers named, and a window of a long text coloured as the whole text colours it.
@Suite("Markdown source highlighting")
struct MarkdownSourceHighlighterTests {
    private typealias Style = MarkdownSourceStyle

    /// The style of each byte of `text`; nil for a byte left plain.
    private func styles(_ text: String, visible: Range<Int>? = nil) -> [Style?] {
        let bytes = Array(text.utf8)
        var result = [Style?](repeating: nil, count: bytes.count)
        for span in MarkdownSourceHighlighter.spans(of: bytes, visible: visible) {
            for offset in span.bytes { result[offset] = span.style }
        }
        return result
    }

    private let marker = Style(kind: .marker)

    @Test func `emphasis, strong and code take their styles, and their markers are marked`() {
        let styles = styles("a **b** _c_ `d`")
        #expect(styles[0] == nil, "plain text is plain")
        #expect(styles[2] == marker && styles[3] == marker, "the ** markers")
        #expect(styles[4] == Style(kind: .text, traits: .strong), "b is strong")
        #expect(styles[9] == Style(kind: .text, traits: .emphasis), "c is emphasis")
        #expect(styles[13] == Style(kind: .code), "d is code")
        #expect(styles[12] == marker && styles[14] == marker, "the backticks")
        #expect(styles[1] == nil && styles[7] == nil, "white space between marks is in none")
    }

    @Test func `strong inside emphasis has both traits, and strikethrough its own`() {
        let styles = styles("_a **b** c_ ~~d~~")
        #expect(styles[1] == Style(kind: .text, traits: .emphasis))
        #expect(styles[5] == Style(kind: .text, traits: [.emphasis, .strong]))
        #expect(styles[14] == Style(kind: .text, traits: .strikethrough))
    }

    @Test func `an ATX heading is a heading of its level, its hashes marked`() {
        let styles = styles("## Title")
        #expect(styles[0] == marker && styles[1] == marker)
        #expect(styles[3] == Style(kind: .text, headingLevel: 2))
    }

    @Test func `a setext heading is not coloured, since its meaning comes from the line below`() {
        #expect(styles("Title\n===")[0] == nil)
    }

    @Test func `a link's text is a link and its target is a target`() {
        let styles = styles("[docs](https://x.y)")
        #expect(styles[1] == Style(kind: .text, traits: .link))
        #expect(styles[8] == Style(kind: .linkTarget))
        #expect(styles[0] == marker && styles[5] == marker, "the brackets")
    }

    @Test func `a fence's lines are code, its info string a label, the fence itself marked`() {
        let styles = styles("```swift\nlet a = 1\n```")
        #expect(styles[0] == marker)
        #expect(styles[3] == Style(kind: .codeLabel))
        #expect(styles[9] == Style(kind: .code), "the code line")
    }

    @Test func `inline html is html`() {
        #expect(styles("a <b>x</b>")[2] == Style(kind: .html))
    }

    @Test func `plain prose has no spans, so it costs nothing`() {
        #expect(MarkdownSourceHighlighter.spans(of: Array("just some words".utf8)).isEmpty)
        #expect(MarkdownSourceHighlighter.spans(of: []).isEmpty)
    }

    @Test func `the runs are in order, do not overlap, and stay inside the text`() {
        let bytes = Array("# T\n\n- a **b** `c` [d](e)\n\n```x\ny\n```\n> q _r_".utf8)
        let spans = MarkdownSourceHighlighter.spans(of: bytes)
        #expect(!spans.isEmpty)
        var end = 0
        for span in spans {
            #expect(span.bytes.lowerBound >= end && !span.bytes.isEmpty)
            #expect(span.bytes.upperBound <= bytes.count)
            end = span.bytes.upperBound
        }
    }

    // MARK: A window of a long text

    private static let pieces = [
        "# Title", "Some **bold** text and `code`.", "", "- one", "- two **x**", "", "  continued item text", "",
        "```swift", "let a = \"**not bold**\"", "", "# not a heading", "```", "", "> quoted _it_", "", "plain line",
        "~~~", "inside", "~~~", "", "    indented code **no**", "", "1. first", "2. [link](https://x.y)", "",
        "- item", "", "    **deep** continuation", "    **more** continuation", ""
    ]

    /// The runs of `bytes` as (offset, style) for each byte inside `visible`.
    private func colours(_ spans: [MarkdownSourceSpan], in visible: Range<Int>) -> [(Int, Style)] {
        spans.flatMap { span in span.bytes.filter(visible.contains).map { ($0, span.style) } }
    }

    private func sameInside(_ bytes: [UInt8], _ visible: Range<Int>) -> Bool {
        let whole = colours(MarkdownSourceHighlighter.spans(of: bytes), in: visible)
        let windowed = colours(MarkdownSourceHighlighter.spans(of: bytes, visible: visible), in: visible)
        return whole.map(\.0) == windowed.map(\.0) && whole.map(\.1) == windowed.map(\.1)
    }

    private func lineStarts(_ lines: [String], joiner: String = "\n") -> [Int] {
        lines.reduce(into: [0]) { $0.append($0.last! + $1.utf8.count + joiner.utf8.count) }
    }

    @Test(arguments: [0, 7, 11, 12, 21, 29, 40, 133, 268, 399, 649, 811, 1_200, 1_487])
    func `a window of a long text is coloured as the whole text colours it`(firstLine: Int) {
        let lines = (0 ..< 1_500).map { Self.pieces[$0 % Self.pieces.count] }
        let bytes = Array(lines.joined(separator: "\n").utf8)
        #expect(bytes.count > MarkdownSourceHighlighter.wholeParseBytes, "long enough to be parsed by window")
        let starts = lineStarts(lines)
        let visible = starts[firstLine] ..< min(starts[min(firstLine + 12, lines.count)], bytes.count)
        #expect(sameInside(bytes, visible), "lines \(firstLine) to \(firstLine + 12)")
    }

    private static let accented = [
        "# Café", "Un **gras** et `code` 🙂.", "", "- un", "- deux **é**", "", "```", "**pas gras** 漢字", "```", "",
        "> cité _é_", "",
        "ligne 🇫🇷 simple", ""
    ]
    private static let crlf = [
        "# Title\r", "Some **bold** and `code`.\r", "\r", "- one\r", "- two **x**", "", "```", "**not bold**", "```",
        "", "> quoted _it_\r", "",
        "plain line", ""
    ]

    @Test(arguments: [13, 268, 811, 1_487], [accented, crlf])
    func `the same with multi-byte characters and with CRLF`(firstLine: Int, pieces: [String]) {
        let lines = (0 ..< 1_500).map { pieces[$0 % pieces.count] }
        let bytes = Array(lines.joined(separator: "\n").utf8)
        let starts = lineStarts(lines)
        let visible = starts[firstLine] ..< min(starts[min(firstLine + 12, lines.count)], bytes.count)
        let whole = colours(MarkdownSourceHighlighter.spans(of: bytes), in: visible)
        #expect(!whole.isEmpty, "the window holds marks to compare")
        #expect(sameInside(bytes, visible), "line \(firstLine)")
    }

    /// Random text made of the pieces that matter, windows at random places: the property of the fixed cases, over many more.
    @Test func `random Markdown, random windows`() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 33)
        }
        let atoms = [
            "# h", "## h2", "- i", "* j", "1. n", "> q", "```", "~~~", "```swift", "    code", "  - nested", "", "",
            "text", "**b**", "_e_", "`c`", "[l](u)",
            "<b>", "~~s~~", "| a | b |", "|---|---|", "---", "===", "\t tab", "&amp;"
        ]
        for round in 0 ..< 60 {
            let lines = (0 ..< 700).map { _ in atoms[next() % atoms.count] }
            let bytes = Array(lines.joined(separator: "\n").utf8)
            let starts = lineStarts(lines)
            let first = next() % (lines.count - 14)
            let visible = starts[first] ..< starts[first + 12]
            #expect(sameInside(bytes, visible), "round \(round), lines \(first) to \(first + 12)")
        }
    }

    // MARK: Hostile input and limits

    @Test func `any bytes are accepted`() {
        var bytes: [UInt8] = []
        for value in 0 ... 255 { bytes += [UInt8(value), UInt8(ascii: "*"), UInt8(ascii: "a"), UInt8(ascii: "*")] }
        let spans = MarkdownSourceHighlighter.spans(of: bytes)
        for span in spans { #expect(span.bytes.upperBound <= bytes.count) }
        // Ill-formed UTF-8, NUL, no line ending, a lone surrogate's bytes.
        _ = MarkdownSourceHighlighter.spans(of: [0xED, 0xA0, 0x80, 0x2A, 0x00, 0xFF, 0x60])
        _ = MarkdownSourceHighlighter.spans(of: [UInt8](repeating: 0x2A, count: 100_000))
    }

    @Test func `a window outside the text, empty, or reversed is held to it`() {
        let bytes = Array((0 ..< 2_000).map { _ in "a **b** `c`" }.joined(separator: "\n").utf8)
        for visible in [
            -50 ..< 20, 0 ..< 0, 5_000_000 ..< 6_000_000, 100 ..< 100, Int.min ..< Int.max, 10 ..< 3_000_000
        ] {
            let spans = MarkdownSourceHighlighter.spans(of: bytes, visible: visible)
            for span in spans { #expect(span.bytes.lowerBound >= 0 && span.bytes.upperBound <= bytes.count) }
        }
    }

    @Test func `a text over the limit is coloured to its last line ending before it and not beyond`() {
        let line = "a **b** `c`\n"
        let bytes = Array(String(repeating: line, count: 1_000).utf8)
        let spans = MarkdownSourceHighlighter.spans(of: bytes, maxBytes: 100)
        let covered = spans.map(\.bytes.upperBound).max() ?? 0
        #expect(covered > 0 && covered <= 100)
        #expect(spans.allSatisfy { $0.bytes.upperBound <= 100 })
        // The bytes past the limit are not claimed as markers just because nothing parsed them.
        #expect(MarkdownSourceHighlighter.spans(of: bytes, maxBytes: 0).isEmpty)
        #expect(MarkdownSourceHighlighter.spans(of: bytes, maxBytes: -5).isEmpty)
    }

    @Test func `a draft that is a keystroke away from being long is parsed in time linear in its size`() {
        let clock = ContinuousClock()
        func time(_ lines: Int) -> Duration {
            let bytes = Array(String(repeating: "- a **b** `c` [d](e)\n", count: lines).utf8)
            return clock.measure { _ = MarkdownSourceHighlighter.spans(of: bytes) }
        }
        let small = time(2_000)
        let large = time(20_000)
        #expect(large < small * 40 + .milliseconds(20), "\(small) for 2,000 lines, \(large) for 20,000")
    }
}
