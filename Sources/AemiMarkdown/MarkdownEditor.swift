/// A document that is edited: bytes replaced anywhere, the blocks that differ told back (ADR-0003, ask roadmap 0203).
///
/// An edit restarts the parse at a line where nothing is open, a block or two before the edit, reads forward until a top-level block of the new text starts
/// where one of the old text did (the edit's shift apart), and splices what it read into the tapes: the cost is the edit's region, the move of the tail, and
/// the shift of its offsets. An edit that cannot be done that way (a link reference definition came or went, the document has a diagnostic, the
/// limits) parses the whole new source, which is the oracle the other is tested against, tape for tape.
///
/// A document the editor holds is a snapshot; let it go before the next edit, or the next edit copies what it shares.
///
/// ```swift
/// var editor = MarkdownEditor(Array("# Title\n\ntext\n".utf8))
/// let change = editor.replace(9 ..< 13, with: Array("words".utf8))
/// for ordinal in change.changedBlocks { draw(editor.document.block(at: ordinal)) }
/// ```
public struct MarkdownEditor: Sendable {
    public let extensions: MarkdownExtensions
    public let limits: MarkdownLimits
    var parser: MarkdownParser
    /// Reads the part of the document an edit touched; keeps the memory it grew.
    var region: MarkdownParser
    /// The new source, built beside the old one, for the parse of the whole.
    private var scratch: [UInt8] = []
    /// Reused from edit to edit: the bytes an edit replaced, and the hashes of the blocks it replaced and of the ones that took their place.
    var removedBytes: [UInt8] = []
    var oldWindow: ContiguousArray<UInt64> = []
    var newWindow: ContiguousArray<UInt64> = []
    /// Whether the last edit was done by the whole parse (for tests and benchmarks).
    public private(set) var lastEditParsedWhole = false

    public init(_ bytes: [UInt8] = [], extensions: MarkdownExtensions = .github, limits: MarkdownLimits = .default) {
        self.extensions = extensions
        self.limits = limits
        parser = MarkdownParser(extensions: extensions, limits: limits)
        region = MarkdownParser(extensions: extensions, limits: limits)
        parser.append(bytes)
        parser.finish()
    }

    /// The document as the last edit left it.
    public var document: MarkdownDocument { parser.document() }

    /// Replaces the bytes in `range` with `bytes`. A range outside the source is cut to it; an edit never fails.
    /// - Returns: the blocks that differ afterwards.
    /// - Complexity: O(the edit's region + the tail's size) when the edit restarts and resyncs; O(document) when it parses whole.
    @discardableResult
    public mutating func replace(_ range: Range<Int>, with bytes: [UInt8]) -> MarkdownChange {
        let count = parser.source.count
        let lower = Swift.min(Swift.max(range.lowerBound, 0), count)
        let upper = Swift.min(Swift.max(range.upperBound, lower), count)
        if let change = resync(lower ..< upper, with: bytes) {
            lastEditParsedWhole = false
            return change
        }
        lastEditParsedWhole = true
        return parseWhole(lower ..< upper, with: bytes)
    }

    /// Parses the new source from the start and compares the hashes of the blocks with the old ones, from both ends.
    private mutating func parseWhole(_ range: Range<Int>, with bytes: [UInt8]) -> MarkdownChange {
        Self.collectHashes(
            into: &oldWindow,
            of: parser,
            from: 0,
            count: parser.topIndex.count / BlockIndex.slotsPerBlock
        )
        // `resync` may have put the bytes in place already; the length of the source says which.
        scratch.removeAll(keepingCapacity: true)
        scratch.reserveCapacity(parser.source.count + bytes.count)
        if parser.spliced {
            scratch.append(contentsOf: parser.source)
        } else {
            scratch.append(contentsOf: parser.source[..<range.lowerBound])
            scratch.append(contentsOf: bytes)
            scratch.append(contentsOf: parser.source[range.upperBound...])
        }
        parser.spliced = false
        parser.reset()
        parser.append(scratch)
        parser.finish()
        Self.collectHashes(
            into: &newWindow,
            of: parser,
            from: 0,
            count: parser.topIndex.count / BlockIndex.slotsPerBlock
        )
        return change(first: 0, replaced: range, insertedBytes: bytes.count)
    }

    /// The content hashes of `count` blocks of `parser` from the one at `ordinal`, in `result`. The document it reads through is let go before it returns.
    /// (Static, with the parser passed in: a method that took `self` while `result` is one of its properties would hold a copy of them, and the array would not be
    /// unique when it is emptied.)
    static func collectHashes(
        into result: inout ContiguousArray<UInt64>,
        of parser: MarkdownParser,
        from ordinal: Int,
        count: Int
    ) {
        result.removeAll(keepingCapacity: true)
        var blocks = parser.document().blocks(from: ordinal)
        while result.count < count, let block = blocks.next() { result.append(block.contentHash) }
    }

    /// The change between two runs of hashes that start at ordinal `first`: what the two ends share is left out.
    func change(first: Int, replaced: Range<Int>, insertedBytes: Int) -> MarkdownChange {
        let old = oldWindow
        let new = newWindow
        let shortest = Swift.min(old.count, new.count)
        var prefix = 0
        while prefix < shortest, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shortest - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        return MarkdownChange(
            replaced: replaced,
            insertedBytes: insertedBytes,
            firstBlock: first + prefix,
            removedBlocks: old.count - prefix - suffix,
            insertedBlocks: new.count - prefix - suffix
        )
    }
}
