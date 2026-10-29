import Testing

@testable import AemiMarkdown

/// The code in the documentation catalog, run, so the articles cannot drift from the API.
@Suite("The documentation's examples run as written")
struct DocumentationExampleTests {
    @Test func `the overview's walk sees the heading, the strong text and the leaves`() {
        let document = MarkdownParser.parse(Array("# Title\n\nSome **bold** text.\n".utf8))
        var entered: [NodeKind] = []
        for event in document.events {
            if case .enter(let node) = event { entered.append(node.kind) }
        }
        #expect(entered.contains(.heading) && entered.contains(.paragraph) && entered.contains(.strong))
    }

    @Test func `the streaming article's parser reads a partial and a finished document`() {
        var parser = MarkdownParser()
        parser.append(Array("# Title\n\nStill being wri".utf8))
        let partial = parser.snapshot()
        #expect(Array(partial.topLevelBlocks).map(\.node.kind) == [.heading, .paragraph])
        parser.append(Array("tten.\n".utf8))
        parser.finish()
        let finished = parser.snapshot()
        #expect(Array(finished.topLevelBlocks).allSatisfy { $0.isFinal })
    }

    @Test func `the rendering article's cache lays out a final block once`() {
        var cache: [Int: [String]] = [:]
        var layouts = 0
        func layOut(_ events: MarkdownEvents) -> [String] {
            layouts += 1
            return events.map { "\($0)" }
        }
        func draw(_ document: MarkdownDocument) -> [String] {
            var rows: [String] = []
            for block in document.topLevelBlocks {
                if let kept = cache[block.id] {
                    rows += kept
                    continue
                }
                let drawn = layOut(document.events(of: block))
                if block.isFinal { cache[block.id] = drawn }
                rows += drawn
            }
            return rows
        }
        var parser = MarkdownParser()
        parser.append(Array("# Title\n\nFirst.\n\nSecond, open".utf8))
        _ = draw(parser.snapshot())
        #expect(layouts == 3)
        parser.append(Array(" still".utf8))
        _ = draw(parser.snapshot())
        #expect(layouts == 4, "only the open paragraph was laid out again")
    }
}
