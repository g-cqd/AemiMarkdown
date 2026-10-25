/// What the block parser keeps between lines: the stack of open blocks, the cursor in the current line, and the lines of the open leaf block.
struct BlockState: Sendable {
    /// The kinds of block that can be open. A leaf that takes one line (`heading`, `thematicBreak`) stays open until the next line, as in cmark.
    enum Kind: UInt8, Sendable {
        case document, blockQuote, list, item, paragraph, heading, thematicBreak, indentedCode, fencedCode, htmlBlock,
            table
    }

    struct Open: Sendable {
        var kind: Kind
        /// Index of the block's slot on the block tape, or -1 for the document.
        var slot: Int
        var startLine: Int
        var lastLineBlank = false
        var hasChild = false
        // What the last closed child said when it closed, to decide whether a list is loose: whether it ended in a blank line itself,
        // what its own last child said, and whether it was a list or an item (only those pass the question down).
        var childSelfBlank = false
        var childInnerBlank = false
        var childIsContainer = false
        /// A list: some item is separated from the next by a blank line, or holds blocks that are.
        var loose = false
        // A list or an item.
        var isOrdered = false
        var markerCharacter: UInt8 = 0
        var markerOffset = 0
        var padding = 0
        // A fenced code block.
        var fenceCharacter: UInt8 = 0
        var fenceLength = 0
        var fenceOffset = 0
        // An HTML block.
        var htmlCondition = 0
        // A table: its column count, and two bits of alignment per column.
        var columns = 0
        var alignments: UInt128 = 0
        // A paragraph or heading: where its lines start in `BlockState.lineRanges`.
        var firstLine = 0
        var lineCount = 0

        /// Whether the last child ends in a blank line, looking through lists and items (cmark's `S_ends_with_blank_line`).
        var lastChildEndsBlank: Bool { childSelfBlank || (childIsContainer && childInnerBlank) }
    }

    /// A leaf block whose inlines are not parsed yet.
    struct Pending: Sendable {
        var slot: Int
        var firstLine: Int
        var lineCount: Int
    }

    /// The state of a new document: only the document is open. The arrays keep the room they grew.
    mutating func reset() {
        open.removeAll(keepingCapacity: true)
        open.append(Open(kind: .document, slot: -1, startLine: 0))
        lineNumber = 0
        lineRanges.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        cells.removeAll(keepingCapacity: true)
        offset = 0
        column = 0
        firstNonspace = 0
        firstNonspaceColumn = 0
        indent = 0
        blank = false
        partiallyConsumedTab = false
    }

    var open: ContiguousArray<Open> = [Open(kind: .document, slot: -1, startLine: 0)]
    var lineNumber = 0
    var lineRanges: ContiguousArray<Range<Int>> = []
    var pending: ContiguousArray<Pending> = []
    /// The cells of the table row being read, as source ranges: scratch that is reused.
    var cells: ContiguousArray<Range<Int>> = []

    // The cursor in the line being processed, as in cmark's parser.
    var offset = 0
    var column = 0
    var firstNonspace = 0
    var firstNonspaceColumn = 0
    var indent = 0
    var blank = false
    var partiallyConsumedTab = false
}
