/// A walk over a document, in document order, with no recursion: the open containers are an explicit stack.
///
/// - Complexity: O(1) per event, apart from the stack's growth, which is bounded by the nesting limits the parser applied.
public struct MarkdownEvents: Sequence, IteratorProtocol, Sendable {
    private let blocks: SlotTape
    private let inlines: SlotTape
    private var blockIndex = 0
    private var blockStack: [(end: Int, node: MarkdownNode)] = []
    private var inlineIndex = 0
    private var inlineStack: [(end: Int, node: MarkdownNode)] = []
    private var leafBlock: MarkdownNode?

    init(blocks: SlotTape, inlines: SlotTape) {
        self.blocks = blocks
        self.inlines = inlines
        blockStack.reserveCapacity(16)
        inlineStack.reserveCapacity(16)
    }

    public mutating func next() -> MarkdownEvent? {
        if let leaf = leafBlock { return nextInline(of: leaf) }
        if let top = blockStack.last, top.end == blockIndex {
            blockStack.removeLast()
            return .exit(top.node)
        }
        guard blockIndex < blocks.count else { return nil }
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
