/// The top-level blocks of a document, in order, skipping each block's subtree in one step.
///
/// - Complexity: O(1) per block.
public struct MarkdownBlocks: Sequence, IteratorProtocol, Sendable {
    private let blocks: SlotTape
    private let blockIndex: SlotTape
    private let stamps: SlotTape
    /// The first pair on the stamp tape not yet passed: stamps are in slot order, as the blocks are.
    private var stampCursor = 0
    private let finalBefore: Int
    private var index = 0
    private var ordinal = 0

    init(blocks: SlotTape, blockIndex: SlotTape, stamps: SlotTape, finalBefore: Int, startingAt ordinal: Int = 0) {
        self.blocks = blocks
        self.blockIndex = blockIndex
        self.stamps = stamps
        self.finalBefore = finalBefore
        let base = ordinal * BlockIndex.slotsPerBlock
        if ordinal > 0, base + 2 < blockIndex.count {
            self.ordinal = ordinal
            index = Int(blockIndex[base + 2])
        } else if ordinal > 0 {
            index = blocks.count  // past the last block: nothing to walk
        }
        // The first stamp at or after the first slot (binary search over the pairs).
        var low = 0
        var high = stamps.count / 2
        while low < high {
            let middle = (low + high) / 2
            if Int(stamps[middle * 2]) < index { low = middle + 1 } else { high = middle }
        }
        stampCursor = low * 2
    }

    public mutating func next() -> MarkdownBlock? {
        guard index < blocks.count else { return nil }
        let start = index
        let slot = blocks[start]
        // A container's `low` is the index after its subtree; any other top-level block is one slot. A corrupt `low` that does not move
        // forward, or runs past the tape, is taken as one slot rather than looping or trapping.
        let end = Slot.shape(slot) == .container ? Slot.low(slot) : start + 1
        index = end > start && end <= blocks.count ? end : start + 1
        // The entry of this ordinal, if it names this block: a tape the index does not match (it never happens) gives an empty range, not a trap.
        let base = ordinal * BlockIndex.slotsPerBlock
        let named = base + 2 < blockIndex.count && Int(blockIndex[base + 2]) == start
        // What the references in the block's leaves resolved to is part of what the block is.
        var hash = named ? blockIndex[base + 1] : 0
        while stampCursor + 1 < stamps.count, Int(stamps[stampCursor]) < index {
            if named { hash = (hash.rotatedLeft(29) ^ stamps[stampCursor + 1]) &* 0x9E37_79B9_7F4A_7C15 }
            stampCursor += 2
        }
        let block = MarkdownBlock(
            id: start,
            node: MarkdownNode(slot: slot),
            isFinal: index <= finalBefore,
            ordinal: ordinal,
            sourceRange: named
                ? BlockIndex.start(blockIndex[base])
                    ..< Swift.max(BlockIndex.start(blockIndex[base]), BlockIndex.end(blockIndex[base])) : 0 ..< 0,
            contentHash: hash,
            slots: start ..< index
        )
        ordinal += 1
        return block
    }
}
