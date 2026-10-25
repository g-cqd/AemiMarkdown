/// A parsed document: the source bytes and the two tapes that name them (ADR-0001).
///
/// A value of this type is a snapshot. It shares storage with the parser that made it, copy-on-write, so holding one while the parser
/// appends costs a copy; read it and let it go.
public struct MarkdownDocument: Sendable {
    /// The input, as the parser received it. Every range in the tapes indexes this array.
    public let source: ContiguousArray<UInt8>
    let blocks: ContiguousArray<UInt64>
    let inlines: ContiguousArray<UInt64>
    public let diagnostics: MarkdownDiagnostics

    init(
        source: ContiguousArray<UInt8>, blocks: ContiguousArray<UInt64>, inlines: ContiguousArray<UInt64>,
        diagnostics: MarkdownDiagnostics
    ) {
        self.source = source
        self.blocks = blocks
        self.inlines = inlines
        self.diagnostics = diagnostics
    }

    /// The document in order, as enter, exit and leaf events.
    public var events: MarkdownEvents { MarkdownEvents(blocks: blocks, inlines: inlines) }

    /// How many slots the block tape holds. For tests and benchmarks.
    public var blockSlotCount: Int { blocks.count }
    /// How many slots the inline tape holds. For tests and benchmarks.
    public var inlineSlotCount: Int { inlines.count }
}
