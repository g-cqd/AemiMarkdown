import Testing

@testable import AemiMarkdown

/// Inputs and settings an attacker or a careless caller can choose, which must neither trap nor make the cost grow out of proportion.
@Suite("The parser holds its bounds against hostile input and settings")
struct HardeningTests {
    /// A slot names at most 4 MiB of source, and a link title can run over many lines, so it is the one range that could exceed that: it must be refused
    /// as a title, not trap when the slot is written. (Before the limits, a 5 MiB title ended the process.)
    @Test func `a link title past the limit is not a title, and does not trap`() {
        let line = String(repeating: "t", count: 1024) + "\n"
        let title = String(repeating: line, count: 200)  // 200 KiB over 200 lines
        let document = MarkdownParser.parse(Array("[a](/u \"\(title)\")\n".utf8))
        #expect(TapeValidator.problem(in: document) == nil)
        #expect(document.diagnostics.contains(.linkLengthLimit))
        #expect(!SpecHTMLRenderer.html(of: document).contains("<a "))
    }

    @Test func `a paragraph of many megabytes with a huge title is plain text, and does not trap`() {
        let line = String(repeating: "t", count: 64 * 1024) + "\n"
        let title = String(repeating: line, count: 80)  // 5 MiB, in one paragraph
        let document = MarkdownParser.parse(Array("[a](/u \"\(title)\")\n".utf8))
        #expect(TapeValidator.problem(in: document) == nil)
        #expect(document.diagnostics.contains(.leafSizeLimit))
    }

    @Test func `a link target as long as the limit allows still is a link`() {
        let target = String(repeating: "x", count: 60 * 1024)
        let html = SpecHTMLRenderer.html(of: MarkdownParser.parse(Array("[a](/\(target))\n".utf8)))
        #expect(html.hasPrefix("<p><a href=\"/xxx"))
    }

    @Test func `limits that would break the tape format are brought inside it`() {
        let limits = MarkdownLimits(
            maxContainerDepth: .max, maxInlineDepth: .max, maxLineBytes: .max, maxDocumentBytes: .max,
            maxTableColumns: .max,
            maxInlineWorkPerByte: .max)
        #expect(limits.maxLineBytes <= Slot.maxRange)
        #expect(limits.maxDocumentBytes <= 1 << 30)
        #expect(limits.maxTableColumns <= 64)
        #expect(limits.maxContainerDepth <= 256)
        #expect(limits.maxInlineDepth <= 256)
        #expect(limits.maxInlineWorkPerByte <= 1024)
        let floor = MarkdownLimits(
            maxContainerDepth: -5, maxInlineDepth: 0, maxLineBytes: 0, maxDocumentBytes: -1, maxTableColumns: 0,
            maxInlineWorkPerByte: -1)
        #expect(
            floor.maxLineBytes >= 1 && floor.maxContainerDepth >= 1 && floor.maxInlineDepth >= 1
                && floor.maxTableColumns >= 1)
        #expect(floor.maxDocumentBytes >= 0 && floor.maxInlineWorkPerByte >= 1)
        // and a parse with the extremes does not trap
        let document = MarkdownParser.parse(Array("# a\n\n| a |\n|---|\n| b |\n".utf8), limits: limits)
        #expect(TapeValidator.problem(in: document) == nil)
    }

    @Test func `a leaf block past the size limit is plain text, and that is reported`() {
        let limits = MarkdownLimits(maxLeafBytes: 64)
        let document = MarkdownParser.parse(Array(String(repeating: "*a ", count: 100).utf8), limits: limits)
        #expect(document.diagnostics.contains(.leafSizeLimit))
        #expect(TapeValidator.problem(in: document) == nil)
        #expect(!SpecHTMLRenderer.html(of: document).contains("<em>"))
    }

    /// Counts the steps of a link at the end of a run of `)`: the closing parentheses are trimmed one at a time, and counting them again each time is quadratic.
    @Test func `a long run of closing parentheses after a bare link costs a linear number of steps`() {
        func cost(_ count: Int) -> Int {
            var parser = MarkdownParser()
            parser.append(Array(("www.example.com/" + String(repeating: ")", count: count) + "\n").utf8))
            parser.finish()
            return parser.inlineSteps
        }
        #expect(cost(40_000) <= cost(20_000) * 3 + 100)
    }

    @Test func `NUL, ESC and DEL are text, kept as bytes, and reported`() {
        let bytes: [UInt8] = Array("a".utf8) + [0, 0x1B, 0x7F] + Array("[b](/c)\n".utf8)
        let document = MarkdownParser.parse(bytes)
        #expect(document.diagnostics.contains(.controlBytes))
        #expect(TapeValidator.problem(in: document) == nil)
        #expect(document.source.contains(0))
    }
}
