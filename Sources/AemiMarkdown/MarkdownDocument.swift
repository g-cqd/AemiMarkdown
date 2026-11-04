/// A parsed document: the source bytes and the two tapes that name them (ADR-0001).
///
/// A value of this type is a snapshot. It shares storage with the parser that made it, copy-on-write, so holding one while the parser
/// appends costs a copy; read it and let it go.
public struct MarkdownDocument: Sendable {
    /// The input, as the parser received it. Every range in the tapes indexes this array.
    public let source: ContiguousArray<UInt8>
    let blocks: SlotTape
    let inlines: SlotTape
    let index: SlotTape
    let stamps: SlotTape
    public let diagnostics: MarkdownDiagnostics
    /// Where the top-level blocks that may still change begin on the block tape.
    let finalBefore: Int

    init(
        source: ContiguousArray<UInt8>,
        blocks: SlotTape,
        inlines: SlotTape,
        index: SlotTape,
        stamps: SlotTape,
        diagnostics: MarkdownDiagnostics,
        finalBefore: Int
    ) {
        self.source = source
        self.blocks = blocks
        self.inlines = inlines
        self.index = index
        self.stamps = stamps
        self.diagnostics = diagnostics
        self.finalBefore = finalBefore
    }

    /// The document in order, as enter, exit and leaf events.
    public var events: MarkdownEvents { MarkdownEvents(blocks: blocks, inlines: inlines) }

    /// The top-level blocks, each with an identity that does not change while the document grows and whether it is final.
    public var topLevelBlocks: MarkdownBlocks {
        MarkdownBlocks(blocks: blocks, blockIndex: index, stamps: stamps, finalBefore: finalBefore)
    }

    /// How many top-level blocks the document has.
    /// - Complexity: O(1).
    public var blockCount: Int { index.count / BlockIndex.slotsPerBlock }

    /// The top-level blocks from the one at `ordinal` on, in order: a host that drew the first blocks of a growing document starts after them, not at the beginning.
    /// - Complexity: O(1) to start, then O(1) per block.
    public func blocks(from ordinal: Int) -> MarkdownBlocks {
        MarkdownBlocks(
            blocks: blocks,
            blockIndex: index,
            stamps: stamps,
            finalBefore: finalBefore,
            startingAt: Swift.max(0, ordinal)
        )
    }

    /// The top-level block at `ordinal`, or nil outside the document.
    /// - Complexity: O(1).
    public func block(at ordinal: Int) -> MarkdownBlock? {
        guard ordinal >= 0, ordinal < blockCount else { return nil }
        var walk = blocks(from: ordinal)
        return walk.next()
    }

    /// The ordinal of the top-level block whose source holds the byte at `offset`, or, for a byte between blocks (blank lines), of the block before it;
    /// nil before the first block or in a document with none.
    /// - Complexity: O(log n) in the number of top-level blocks.
    public func blockOrdinal(containing offset: Int) -> Int? {
        var low = 0
        var high = blockCount - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if BlockIndex.start(index[middle * BlockIndex.slotsPerBlock]) <= offset {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }

    /// The walk over one top-level block, as ``events`` walks the whole document.
    public func events(of block: MarkdownBlock) -> MarkdownEvents {
        MarkdownEvents(blocks: blocks, inlines: inlines, slots: block.slots)
    }

    /// How many slots the block tape holds. For tests and benchmarks.
    public var blockSlotCount: Int { blocks.count }
    /// How many slots the inline tape holds. For tests and benchmarks.
    public var inlineSlotCount: Int { inlines.count }
}
