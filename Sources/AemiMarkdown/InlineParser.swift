/// The inline phase: turns the lines of one leaf block into a tree of nodes (CommonMark 6, as cmark's `inlines.c` does) and then into a run of slots.
///
/// The parser owns scratch buffers it reuses, so after the first few leaf blocks a parse allocates nothing.
struct InlineParser {
    struct Delimiter {
        var node: Int32
        var character: UInt8
        var count: Int
        var originalCount: Int
        var canOpen: Bool
        var canClose: Bool
        var previous: Int32
        var next: Int32
    }

    struct Bracket {
        var node: Int32
        var previousDelimiter: Int32
        /// Where the text after the bracket starts, so a shortcut reference can take its label from here.
        var index: Int
        var isImage: Bool
        var active = true
        var bracketAfter = false
    }

    var tree = InlineTree()
    /// The leaf block's lines joined by line feeds, so a construct that spans lines is one contiguous scan.
    var text: ContiguousArray<UInt8> = []
    var lineScratchStart: ContiguousArray<Int> = []
    var lineSourceStart: ContiguousArray<Int> = []
    var position = 0
    var delimiters: ContiguousArray<Delimiter> = []
    var delimiterTop: Int32 = -1
    var brackets: ContiguousArray<Bracket> = []
    var openersBottom = [Int32](repeating: -1, count: 18)
    var references = ReferenceTable()
    var limits = MarkdownLimits.default
    var extensions = MarkdownExtensions.github
    var work = 0
    var workLimit = 0
    var diagnostics: MarkdownDiagnostics = []
    /// Bit `n` is set when no closing run of `n` backticks follows the position scanned from (for `n` up to 64): two words, so a parse starts with two stores.
    var backticksExhaustedLow: UInt64 = 0
    var backticksExhaustedHigh: UInt64 = 0
    /// No closing `$` follows the position scanned from, and no closing `$$` does: a later opener cannot find one either.
    var singleDollarExhausted = false
    var doubleDollarExhausted = false
    var source: ContiguousArray<UInt8> = []
    /// Scratch indices of the `|` whose backslash was left out of the text (a table cell: `\|` is a pipe even in a code span), ascending.
    var droppedBackslashes: ContiguousArray<Int> = []
    /// The lines of a code span's content, reused from one span to the next.
    var codePieces: [Range<Int>] = []
    /// The containers open while the tree is written as slots, reused from one leaf block to the next.
    var serializeStack: [(slot: Int, node: Int32)] = []
    /// The bare links found in one text node, reused.
    var bareLinks: [BareLink] = []
    /// The normalized form of the label being looked up, reused.
    var referenceKey: [UInt8] = []

    /// Parses `lines` of `source` and appends the leaf block's inline run, ending in a `runEnd` slot, to `inlines`. Returns the index of the run's first slot.
    mutating func parse(
        source: ContiguousArray<UInt8>, lines: ArraySlice<Range<Int>>, references: ReferenceTable,
        limits: MarkdownLimits, extensions: MarkdownExtensions, isTableCell: Bool = false,
        isTaskCandidate: Bool = false,
        into inlines: inout SlotTape
    ) -> Int {
        self.source = source
        self.references = references
        self.limits = limits
        self.extensions = extensions
        tree.reset()
        text.removeAll(keepingCapacity: true)
        lineScratchStart.removeAll(keepingCapacity: true)
        lineSourceStart.removeAll(keepingCapacity: true)
        // The next three are empty for most leaf blocks, and clearing an empty array still costs a call.
        if !delimiters.isEmpty { delimiters.removeAll(keepingCapacity: true) }
        if !brackets.isEmpty { brackets.removeAll(keepingCapacity: true) }
        if !droppedBackslashes.isEmpty { droppedBackslashes.removeAll(keepingCapacity: true) }
        delimiterTop = -1
        position = 0
        work = 0
        backticksExhaustedLow = 0
        backticksExhaustedHigh = 0
        singleDollarExhausted = false
        doubleDollarExhausted = false
        var remaining = lines.count
        for line in lines {
            remaining -= 1
            var range = line
            if remaining == 0 {
                while range.upperBound > range.lowerBound, BlockScanner.isSpaceOrTab(source[range.upperBound - 1]) {
                    range = range.lowerBound ..< (range.upperBound - 1)
                }
            }
            lineScratchStart.append(text.count)
            lineSourceStart.append(range.lowerBound)
            if isTableCell {
                appendTableCell(source[range])
            } else {
                text.append(contentsOf: source[range])
            }
            if remaining > 0 { text.append(0x0A) }
        }
        workLimit = limits.maxInlineWorkPerByte * (text.count + 16)
        if text.count > limits.maxLeafBytes {
            // Memory for the tree would be in proportion to the block, so a block this large is shown as it was written.
            diagnostics.insert(.leafSizeLimit)
            appendPlainLines()
        } else {
            if isTaskCandidate { readTaskMarker() }
            while position < text.count { parseInline() }
            processEmphasis(bottom: -1)
        }
        if extensions.contains(.autolinks), text.count <= limits.maxLeafBytes, mayHoldBareLink() { autolinkBareLinks() }
        let run = inlines.count
        serialize(into: &inlines)
        inlines.append(Slot.make(.marker, .runEnd, payload: 0, low: 0))
        // Let go of the parser's arrays: holding them would make the next change to them copy the whole buffer (and a reused parser allocate one per document).
        self.source = []
        self.references = ReferenceTable()
        return run
    }

    /// The leaf block as text and soft breaks, with no inline syntax read.
    private mutating func appendPlainLines() {
        for line in lineScratchStart.indices {
            var start = lineScratchStart[line]
            let end = line + 1 < lineScratchStart.count ? lineScratchStart[line + 1] - 1 : text.count
            // A lazy continuation line keeps its leading whitespace until here; plain text drops it, as a soft break does.
            while line > 0, start < end, text[start] == 0x20 || text[start] == 0x09 { start += 1 }
            if line > 0 { tree.append(InlineNode(kind: .softBreak)) }
            appendText(start, end, joining: false)
        }
    }

    /// The source offset of the byte at `index` in the joined text.
    func sourceOffset(_ index: Int) -> Int {
        // One line and no dropped backslash, which is nearly every leaf block: no search.
        if lineScratchStart.count == 1, droppedBackslashes.isEmpty { return lineSourceStart[0] + index }
        var low = 0
        var high = lineScratchStart.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineScratchStart[middle] <= index { low = middle } else { high = middle - 1 }
        }
        var offset = lineSourceStart[low] + (index - lineScratchStart[low])
        if !droppedBackslashes.isEmpty {
            var below = 0
            var above = droppedBackslashes.count
            while below < above {
                let middle = (below + above) / 2
                if droppedBackslashes[middle] <= index { below = middle + 1 } else { above = middle }
            }
            offset += below
        }
        return offset
    }

    /// Appends a table cell's bytes with the backslash taken out of each `\|`, which is how a table writes a pipe that does not divide cells.
    private mutating func appendTableCell(_ bytes: ArraySlice<UInt8>) {
        var previous: UInt8 = 0
        for byte in bytes {
            if byte == UInt8(ascii: "|"), previous == UInt8(ascii: "\\") {
                text.removeLast()
                droppedBackslashes.append(text.count)
            }
            text.append(byte)
            previous = byte == UInt8(ascii: "\\") && previous == UInt8(ascii: "\\") ? 0 : byte
        }
    }

    /// Counts a step of work against the leaf block's budget; false once it is spent (and `inlineWorkLimit` is noted).
    mutating func spend(_ steps: Int = 1) -> Bool {
        work += steps
        if work > workLimit {
            diagnostics.insert(.inlineWorkLimit)
            return false
        }
        return true
    }

    @discardableResult
    mutating func appendNode(_ kind: NodeKind, scratch start: Int, length: Int, payload: Int = 0) -> Int32 {
        tree.append(InlineNode(kind: kind, payload: payload, start: sourceOffset(start), length: length))
    }

    /// The first scratch index in `lower ..< upper` of a pipe whose backslash was left out, if any.
    private func firstDroppedBackslash(in lower: Int, _ upper: Int) -> Int? {
        var below = 0
        var above = droppedBackslashes.count
        while below < above {
            let middle = (below + above) / 2
            if droppedBackslashes[middle] < lower { below = middle + 1 } else { above = middle }
        }
        return below < droppedBackslashes.count && droppedBackslashes[below] < upper ? droppedBackslashes[below] : nil
    }

    /// Adds `text[start ..< end]`, which lies in one line, as text under `parent`: split where a backslash was left out, so each piece names contiguous
    /// source bytes. With `joining`, a piece that touches the text before it extends it.
    mutating func appendText(_ start: Int, _ end: Int, to parent: Int32 = InlineTree.root, joining: Bool = true) {
        var from = start
        while from < end {
            var upto = end
            if !droppedBackslashes.isEmpty, let dropped = firstDroppedBackslash(in: from + 1, end) { upto = dropped }
            let sourceStart = sourceOffset(from)
            let last = tree.nodes[Int(parent)].lastChild
            if joining, last >= 0, tree.nodes[Int(last)].kind == .text, tree.nodes[Int(last)].payload == 0,
                tree.nodes[Int(last)].start + tree.nodes[Int(last)].length == sourceStart
            {
                tree.nodes[Int(last)].length += upto - from
            } else {
                tree.append(InlineNode(kind: .text, start: sourceStart, length: upto - from), to: parent)
            }
            from = upto
        }
    }

    mutating func parseInline() {
        let byte = text[position]
        switch byte {
            case 0x0A: newline()
            case 0x5C: backslash()
            case 0x60: backticks()
            case 0x2A, 0x5F: delimiterRun(byte)
            case 0x7E: if extensions.contains(.strikethrough) { delimiterRun(byte) } else { plain() }
            case 0x5B: openBracket(isImage: false)
            case 0x21:
                if position + 1 < text.count, text[position + 1] == 0x5B { openBracket(isImage: true) } else { plain() }
            case 0x5D: closeBracket()
            case 0x24: dollar()
            case 0x3C: angle()
            case 0x26: entity()
            default: plain()
        }
    }

    /// Plain text up to the next byte that can start something.
    private mutating func plain() {
        let start = position
        position = ByteScan.firstIndex(inSet: ByteScan.inlineSpecials, in: text, from: position + 1)
        appendText(start, position)
    }

    /// A task list marker at the start of the text: `[ ]`, `[x]` or `[X]`, then a space, a tab, a line ending or the end. It becomes a marker, and what follows it is the item's text.
    private mutating func readTaskMarker() {
        guard text.count >= 3, text[0] == UInt8(ascii: "["), text[2] == UInt8(ascii: "]") else { return }
        let state = text[1]
        guard state == 0x20 || state == UInt8(ascii: "x") || state == UInt8(ascii: "X") else { return }
        guard text.count == 3 || text[3] == 0x20 || text[3] == 0x09 || text[3] == 0x0A else { return }
        tree.append(InlineNode(kind: .taskMarker, payload: state == 0x20 ? 0 : 1))
        position = 3
        while position < text.count, text[position] == 0x20 || text[position] == 0x09 { position += 1 }
    }

    private mutating func newline() {
        // White space before the line ending is not text. Two spaces right before it make a hard break, anything less a soft one (a tab does not count).
        var spaces = 0
        let last = tree.nodes[0].lastChild
        if last >= 0, tree.nodes[Int(last)].kind == .text, tree.nodes[Int(last)].payload == 0 {
            let node = tree.nodes[Int(last)]
            var end = node.start + node.length
            while end > node.start, source[end - 1] == 0x20 || source[end - 1] == 0x09 { end -= 1 }
            var run = node.start + node.length
            while run > end, source[run - 1] == 0x20 { run -= 1 }
            spaces = node.start + node.length - run
            tree.nodes[Int(last)].length = end - node.start
        }
        tree.append(InlineNode(kind: spaces >= 2 ? .hardBreak : .softBreak))
        position += 1
        while position < text.count, text[position] == 0x20 || text[position] == 0x09 { position += 1 }
    }

    private mutating func backslash() {
        let next = position + 1 < text.count ? text[position + 1] : 0
        if next == 0x0A {
            // The next line's leading spaces stay, as in cmark: only a lazy continuation line still has any.
            tree.append(InlineNode(kind: .hardBreak))
            position += 2
        } else if next != 0, ASCIIClass.isPunctuation(next) {
            tree.append(InlineNode(kind: .text, start: sourceOffset(position + 1), length: 1))
            position += 2
        } else {
            appendText(position, position + 1)
            position += 1
        }
    }

    private mutating func entity() {
        if let length = CharacterReference.length(text, at: position) {
            tree.append(InlineNode(kind: .entity, start: sourceOffset(position), length: length))
            position += length
        } else {
            appendText(position, position + 1)
            position += 1
        }
    }
}
