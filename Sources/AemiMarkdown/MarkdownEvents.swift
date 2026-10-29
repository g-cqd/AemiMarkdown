/// A walk over a document, in document order, with no recursion: the open containers are an explicit stack.
///
/// - Complexity: O(1) per event, apart from the stack's growth, which is bounded by the nesting limits the parser applied.
public struct MarkdownEvents: Sequence, IteratorProtocol, Sendable {
    private var blocks: SlotTape
    private var inlines: SlotTape
    private var blockIndex = 0
    /// Where the walk stops on the block tape: its end, or the end of one top-level block.
    private var blockEnd: Int
    private var blockStack: [(end: Int, node: MarkdownNode)] = []
    private var inlineIndex = 0
    private var inlineStack: [(end: Int, node: MarkdownNode)] = []
    private var leafBlock: MarkdownNode?

    init(blocks: SlotTape, inlines: SlotTape, slots: Range<Int>? = nil) {
        self.blocks = blocks
        self.inlines = inlines
        let slots = slots ?? 0 ..< blocks.count
        blockIndex = Swift.max(0, slots.lowerBound)
        blockEnd = Swift.min(blocks.count, slots.upperBound)
        blockStack.reserveCapacity(16)
        inlineStack.reserveCapacity(16)
    }

    /// Walks `block` of `document` from its start, keeping the memory the walk's stacks grew: a renderer that keeps one walker for the blocks it lays
    /// out allocates nothing per walk once the stacks are as deep as its deepest block.
    public mutating func restart(at block: MarkdownBlock, in document: MarkdownDocument) {
        blocks = document.blocks
        inlines = document.inlines
        blockIndex = Swift.max(0, block.slots.lowerBound)
        blockEnd = Swift.min(blocks.count, block.slots.upperBound)
        blockStack.removeAll(keepingCapacity: true)
        inlineStack.removeAll(keepingCapacity: true)
        inlineIndex = 0
        leafBlock = nil
    }

    public mutating func next() -> MarkdownEvent? {
        if let leaf = leafBlock { return nextInline(of: leaf) }
        if let top = blockStack.last, top.end == blockIndex {
            blockStack.removeLast()
            return .exit(top.node)
        }
        guard blockIndex < blockEnd else { return nil }
        let slot = blocks[blockIndex]
        blockIndex += 1
        let node = MarkdownNode(slot: slot)
        switch Slot.shape(slot) {
            case .container:
                blockStack.append((Slot.low(slot), node))
                return .enter(node)
            case .leafBlock:
                leafBlock = node
                inlineIndex = Slot.low(slot)
                return .enter(node)
            case .range, .marker:
                return .leaf(node)
        }
    }

    private mutating func nextInline(of leaf: MarkdownNode) -> MarkdownEvent? {
        if let top = inlineStack.last, top.end == inlineIndex {
            inlineStack.removeLast()
            return .exit(top.node)
        }
        // A run always ends in a `runEnd` slot, so a missing one means a corrupt tape: stop the run rather than trap.
        guard inlineIndex < inlines.count, Slot.kind(inlines[inlineIndex]) != .runEnd else {
            leafBlock = nil
            inlineStack.removeAll(keepingCapacity: true)
            return .exit(leaf)
        }
        let slot = inlines[inlineIndex]
        inlineIndex += 1
        let node = MarkdownNode(slot: slot)
        if Slot.shape(slot) == .container {
            inlineStack.append((Slot.low(slot), node))
            return .enter(node)
        }
        return .leaf(node)
    }
}
