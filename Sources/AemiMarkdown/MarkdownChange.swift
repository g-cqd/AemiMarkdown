/// What an edit did to the top-level blocks of a document (ADR-0003): which blocks a renderer must draw again, and how the others moved.
///
/// Blocks are compared by content hash, from both ends, so the answer is the smallest run of blocks that differs: a block that is the same bytes,
/// meaning the same links, is not in it, wherever it stands now.
public struct MarkdownChange: Sendable, Equatable {
    /// The bytes of the old source that were replaced.
    public var replaced: Range<Int>
    /// How many bytes took their place.
    public var insertedBytes: Int
    /// The ordinal of the first block that differs; every block before it is the same block at the same ordinal and the same place.
    public var firstBlock: Int
    /// How many blocks of the old document are gone from `firstBlock` on.
    public var removedBlocks: Int
    /// How many blocks of the new document are there from `firstBlock` on: the ones to draw again.
    public var insertedBlocks: Int

    public init(replaced: Range<Int>, insertedBytes: Int, firstBlock: Int, removedBlocks: Int, insertedBlocks: Int) {
        self.replaced = replaced
        self.insertedBytes = insertedBytes
        self.firstBlock = firstBlock
        self.removedBlocks = removedBlocks
        self.insertedBlocks = insertedBlocks
    }

    /// Nothing a reader of the blocks can tell changed (the edit was in white space between blocks, or put back what was there).
    public var isEmpty: Bool { removedBlocks == 0 && insertedBlocks == 0 }

    /// How far every byte after the edit moved.
    public var byteShift: Int { insertedBytes - replaced.count }

    /// How far every block after the changed run moved in the list of blocks.
    public var blockShift: Int { insertedBlocks - removedBlocks }

    /// The ordinals, in the new document, of the blocks to draw again.
    public var changedBlocks: Range<Int> { firstBlock ..< (firstBlock + insertedBlocks) }

    /// Where an ordinal of the old document stands in the new one: the same block moved, or, for a block that was replaced, the first block that replaced it
    /// (so a caret or a scroll position snaps to the nearest block that exists). Nil for an ordinal that never existed.
    public func newOrdinal(ofOld ordinal: Int) -> Int? {
        guard ordinal >= 0 else { return nil }
        if ordinal < firstBlock { return ordinal }
        if ordinal < firstBlock + removedBlocks { return firstBlock }
        return ordinal + blockShift
    }

    /// Where a byte offset of the old source stands in the new one: before the edit, the same; after it, shifted; inside the replaced bytes, at the start of what replaced them.
    public func newOffset(ofOld offset: Int) -> Int {
        if offset <= replaced.lowerBound { return offset }
        if offset >= replaced.upperBound { return offset + byteShift }
        return replaced.lowerBound
    }
}
