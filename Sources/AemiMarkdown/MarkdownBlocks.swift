/// The top-level blocks of a document, in order, skipping each block's subtree in one step.
///
/// - Complexity: O(1) per block.
public struct MarkdownBlocks: Sequence, IteratorProtocol, Sendable {
    private let blocks: SlotTape
    private let finalBefore: Int
    private var index = 0

    init(blocks: SlotTape, finalBefore: Int) {
        self.blocks = blocks
        self.finalBefore = finalBefore
    }

    public mutating func next() -> MarkdownBlock? {
        guard index < blocks.count else { return nil }
        let start = index
        let slot = blocks[start]
        // A container's `low` is the index after its subtree; any other top-level block is one slot. A corrupt `low` that does not move
        // forward, or runs past the tape, is taken as one slot rather than looping or trapping.
        let end = Slot.shape(slot) == .container ? Slot.low(slot) : start + 1
        index = end > start && end <= blocks.count ? end : start + 1
        return MarkdownBlock(
            id: start, node: MarkdownNode(slot: slot), isFinal: index <= finalBefore, slots: start ..< index)
    }
}
