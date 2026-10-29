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
    /// The block's slots on the block tape.
    let slots: Range<Int>
}
