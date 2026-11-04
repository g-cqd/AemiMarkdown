import Foundation
import Testing

@testable import AemiMarkdown

/// The block index on real documents: the public corpus (`PublicCorpus`).
@Suite(
    "The block index on the public corpus",
    .enabled(if: PublicCorpus.isAvailable, "no corpus: run Benchmarks/Corpus/fetch.py setup")
)
struct CorpusIndexTests {
    @Test
    func `every document: the entries are ordered, apart, inside the source and non-empty, and as many as the blocks`()
    {
        for (number, bytes) in PublicCorpus.documents(upTo: 4_000_000).enumerated() {
            let document = MarkdownParser.parse(bytes)
            var count = 0
            var previousEnd = 0
            for block in document.topLevelBlocks {
                #expect(block.ordinal == count, "document \(number)")
                #expect(
                    block.sourceRange.lowerBound >= previousEnd && block.sourceRange.upperBound <= bytes.count,
                    "document \(number) block \(count)"
                )
                #expect(!block.sourceRange.isEmpty, "document \(number) block \(count)")
                previousEnd = block.sourceRange.upperBound
                count += 1
            }
            #expect(count == document.blockCount, "document \(number)")
        }
    }

    @Test func `every block of every document parsed alone is one block of the same kind and the same hash`() {
        var checked = 0
        for (number, bytes) in PublicCorpus.documents(upTo: 500_000).enumerated() {
            let document = MarkdownParser.parse(bytes)
            for block in document.topLevelBlocks {
                let alone = Array(MarkdownParser.parse(Array(document.source[block.sourceRange])).topLevelBlocks)
                #expect(alone.count == 1, "document \(number) block \(block.ordinal) is \(alone.count) blocks alone")
                if let one = alone.first {
                    #expect(
                        one.node.kind == block.node.kind
                            && (document.stamps.count > 0 || one.contentHash == block.contentHash),
                        "document \(number) block \(block.ordinal)"
                    )
                }
                checked += 1
            }
        }
        #expect(checked > 1000)
    }

    @Test func `a document streamed in pieces has the entries of the document parsed whole`() {
        for (number, bytes) in PublicCorpus.documents(upTo: 200_000).enumerated().filter({ $0.offset % 7 == 0 }) {
            let whole = MarkdownParser.parse(bytes)
            var parser = MarkdownParser()
            var offset = 0
            while offset < bytes.count {
                parser.append(Array(bytes[offset ..< min(bytes.count, offset + 37)]))
                offset += 37
            }
            parser.finish()
            let streamed = parser.snapshot()
            #expect(
                streamed.topLevelBlocks.map {
                    [$0.sourceRange.lowerBound, $0.sourceRange.upperBound, Int(truncatingIfNeeded: $0.contentHash)]
                }
                    == whole.topLevelBlocks.map {
                        [$0.sourceRange.lowerBound, $0.sourceRange.upperBound, Int(truncatingIfNeeded: $0.contentHash)]
                    },
                "document \(number)"
            )
        }
    }
}
