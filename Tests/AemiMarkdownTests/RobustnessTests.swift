import Testing

@testable import AemiMarkdown

/// Any bytes give a well-formed document, and what an attacker can make large is bounded (ADR-0001, decision 5).
@Suite("The parser takes any bytes and keeps its bounds")
struct RobustnessTests {
    /// A small deterministic generator, so a failure names a seed that reproduces it.
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Markdown's own bytes are most of the alphabet, so that random input forms constructs, with a few arbitrary bytes among them.
    static func randomInput(seed: UInt64) -> [UInt8] {
        var generator = Generator(state: seed)
        let alphabet = Array("\n\n  \t>>-*_`#[]()!<>&;:|\\~=1.abcXYZ \"'".utf8)
        let length = Int.random(in: 0 ... 400, using: &generator)
        return (0 ..< length)
            .map { _ in
                Int.random(in: 0 ..< 10, using: &generator) == 0
                    ? UInt8.random(in: 0 ... 255, using: &generator) : alphabet.randomElement(using: &generator)!
            }
    }

    @Test(arguments: 0 ..< 40)
    func `random bytes give well-formed tapes, whole or in pieces`(batch: Int) {
        for offset in 0 ..< 50 {
            let seed = UInt64(batch * 50 + offset)
            let bytes = Self.randomInput(seed: seed)
            let whole = MarkdownParser.parse(bytes)
            #expect(TapeValidator.problem(in: whole) == nil, "seed \(seed): \(TapeValidator.problem(in: whole) ?? "")")
            var generator = Generator(state: seed &+ 1)
            var parser = MarkdownParser()
            var rest = bytes[...]
            while !rest.isEmpty {
                let size = Swift.min(rest.count, Int.random(in: 1 ... 9, using: &generator))
                parser.append(Array(rest.prefix(size)))
                rest = rest.dropFirst(size)
                let snapshot = parser.snapshot()
                #expect(
                    TapeValidator.problem(in: snapshot) == nil,
                    "seed \(seed) snapshot: \(TapeValidator.problem(in: snapshot) ?? "")")
            }
            parser.finish()
            let streamed = parser.snapshot()
            let streamedSlots = (0 ..< streamed.blocks.count).map { streamed.blocks[$0] }
            let wholeSlots = (0 ..< whole.blocks.count).map { whole.blocks[$0] }
            #expect(streamedSlots == wholeSlots, "seed \(seed): block tapes differ")
            #expect(streamed.inlineSlotCount == whole.inlineSlotCount, "seed \(seed): inline tapes differ")
        }
    }

    @Test func `control bytes and invalid UTF-8 are text, and are reported`() {
        let escape = MarkdownParser.parse(Array("a \u{1B}]52;c;aGk=\u{07} b".utf8))
        #expect(escape.diagnostics.contains(.controlBytes))
        #expect(TapeValidator.problem(in: escape) == nil)
        let invalid = MarkdownParser.parse([0x61, 0xFF, 0xC0, 0x80, 0x62])
        #expect(invalid.diagnostics.contains(.invalidUTF8))
        #expect(TapeValidator.problem(in: invalid) == nil)
        #expect(MarkdownParser.parse(Array("tab\there\nand text".utf8)).diagnostics.isEmpty)
    }

    @Test func `quotes nested far past the limit are kept as text, within the limit`() {
        let bytes = Array((String(repeating: ">", count: 5_000) + " deep\n").utf8)
        let document = MarkdownParser.parse(bytes)
        #expect(document.diagnostics.contains(.containerDepthLimit))
        #expect(TapeValidator.problem(in: document) == nil)
        var depth = 0
        var deepest = 0
        for case .enter(let node) in document.events where node.kind == .blockQuote {
            depth += 1
            deepest = Swift.max(deepest, depth)
        }
        #expect(deepest <= MarkdownLimits.default.maxContainerDepth)
    }

    @Test func `lists nested far past the limit are kept as text, within the limit`() {
        let bytes = Array((0 ..< 2_000).map { String(repeating: " ", count: 2 * $0) + "- x\n" }.joined().utf8)
        let document = MarkdownParser.parse(bytes)
        #expect(document.diagnostics.contains(.containerDepthLimit))
        #expect(TapeValidator.problem(in: document) == nil)
    }

    @Test func `a line longer than the limit is cut, and the cut is reported`() {
        let limits = MarkdownLimits(maxLineBytes: 16)
        let document = MarkdownParser.parse(Array(String(repeating: "word ", count: 20).utf8), limits: limits)
        #expect(document.diagnostics.contains(.lineLengthLimit))
        #expect(TapeValidator.problem(in: document) == nil)
    }

    @Test func `input past the document limit is ignored, and that is reported`() {
        var parser = MarkdownParser(limits: MarkdownLimits(maxDocumentBytes: 10))
        parser.append(Array("0123456789 and then more".utf8))
        parser.finish()
        let document = parser.snapshot()
        #expect(document.source.count == 10)
        #expect(document.diagnostics.contains(.documentSizeLimit))
    }

    @Test func `a table wider than the limit is a paragraph, and that is reported`() {
        let limits = MarkdownLimits(maxTableColumns: 3)
        let document = MarkdownParser.parse(Array("| a | b | c | d |\n| - | - | - | - |\n".utf8), limits: limits)
        #expect(document.diagnostics.contains(.tableColumnLimit))
        #expect(SpecHTMLRenderer.html(of: document).hasPrefix("<p>"))
    }

    /// Work in the inline phase, counted in steps, for `unit` repeated `count` times.
    private func steps(_ unit: String, _ count: Int) -> Int {
        var parser = MarkdownParser()
        parser.append(Array(String(repeating: unit, count: count).utf8))
        parser.finish()
        return parser.inlineSteps
    }

    /// Doubling the input must not much more than double the work: the shapes below are the ones that make a naive parser quadratic or worse
    /// (cmark's pathological list). A ratio is deterministic where a clock is not.
    @Test(arguments: [
        "*a ", "_a ", "[", "[a](", "`a", "``a ", "*a_ ", "[a][", "![", "<a ", "&a", "**a *b ", "~~a ~b ", "[a]: b\n",
        "> ", "- "
    ])
    func `the inline work grows in step with the input`(unit: String) {
        let small = steps(unit, 4_000)
        let large = steps(unit, 8_000)
        #expect(large <= small * 3 + 100, "\(unit.debugDescription): \(small) steps for 4000 units, \(large) for 8000")
    }
}
