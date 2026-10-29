/// A parsed document: the source bytes and the two tapes that name them (ADR-0001).
///
/// A value of this type is a snapshot. It shares storage with the parser that made it, copy-on-write, so holding one while the parser
/// appends costs a copy; read it and let it go.
public struct MarkdownDocument: Sendable {
    /// The input, as the parser received it. Every range in the tapes indexes this array.
    public let source: ContiguousArray<UInt8>
    let blocks: SlotTape
    let inlines: SlotTape
    public let diagnostics: MarkdownDiagnostics
    /// Where the top-level blocks that may still change begin on the block tape.
    let finalBefore: Int

    init(
        source: ContiguousArray<UInt8>, blocks: SlotTape, inlines: SlotTape,
        diagnostics: MarkdownDiagnostics, finalBefore: Int
    ) {
        self.source = source
        self.blocks = blocks
        self.inlines = inlines
        self.diagnostics = diagnostics
        self.finalBefore = finalBefore
    }

    /// The document in order, as enter, exit and leaf events.
    public var events: MarkdownEvents { MarkdownEvents(blocks: blocks, inlines: inlines) }

    /// The top-level blocks, each with an identity that does not change while the document grows and whether it is final.
    public var topLevelBlocks: MarkdownBlocks { MarkdownBlocks(blocks: blocks, finalBefore: finalBefore) }

    /// The walk over one top-level block, as ``events`` walks the whole document.
    public func events(of block: MarkdownBlock) -> MarkdownEvents {
        MarkdownEvents(blocks: blocks, inlines: inlines, slots: block.slots)
    }

    /// How many slots the block tape holds. For tests and benchmarks.
    public var blockSlotCount: Int { blocks.count }
    /// How many slots the inline tape holds. For tests and benchmarks.
    public var inlineSlotCount: Int { inlines.count }
}
