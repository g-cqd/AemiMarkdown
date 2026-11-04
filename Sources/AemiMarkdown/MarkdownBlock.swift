/// A top-level block of a document, as a renderer caches it: an identity that does not change while the document grows, and whether the block
/// is final.
///
/// A renderer lays a final block out once and keeps its rows; only the block that is not final yet, the last one of a streamed document, is laid
/// out again after an append. The identity is the block's place on the block tape, which a closed block never leaves (ADR-0001, decision 3), so
/// the same block has the same identity in every snapshot and in the finished document.
public struct MarkdownBlock: Sendable, Equatable, Identifiable {
    /// Stable for the life of the document: the same block, in a later snapshot or in the finished document, has the same identity.
    public let id: Int
    /// What the block is: its kind and payload.
    public let node: MarkdownNode
    /// Whether no later input can change the block: it has closed in the parser, not only in the snapshot's provisional reading of a partial
    /// last line. Every block of a finished document is final.
    public let isFinal: Bool
    /// The block's place among the top-level blocks of this document, from 0. Unlike ``id`` it is an index in this snapshot's list, not a name that
    /// outlives it: a block that arrives above shifts it.
    public let ordinal: Int
    /// The block's source: from the first byte of its first line to its last byte that is not white space (ADR-0003). Empty for a node no top-level
    /// block of the parser made.
    public let sourceRange: Range<Int>
    /// What the block is, by its bytes: wyhash (Aemi's `WyHash`) of ``sourceRange`` seeded with the block's kind. Equal for equal blocks wherever they stand, and a key a
    /// renderer can cache its rows by. It does not yet say what a reference link in the block resolves to (ADR-0003).
    public let contentHash: UInt64
    /// The block's slots on the block tape.
    let slots: Range<Int>
}
