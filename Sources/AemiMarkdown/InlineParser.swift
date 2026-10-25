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
    var extensions = MarkdownExtensions.all
    var work = 0
    var workLimit = 0
    var diagnostics: MarkdownDiagnostics = []
    var backticksExhausted = [Bool](repeating: false, count: 65)
    var source: ContiguousArray<UInt8> = []
    /// Scratch indices of the `|` whose backslash was left out of the text (a table cell: `\|` is a pipe even in a code span), ascending.
    var droppedBackslashes: ContiguousArray<Int> = []

    /// Parses `lines` of `source` and appends the leaf block's inline run, ending in a `runEnd` slot, to `inlines`. Returns the index of the run's first slot.
    mutating func parse(
        source: ContiguousArray<UInt8>, lines: ArraySlice<Range<Int>>, references: ReferenceTable,
        limits: MarkdownLimits, extensions: MarkdownExtensions, isTableCell: Bool = false,
        into inlines: inout ContiguousArray<UInt64>
    ) -> Int {
        self.source = source
        self.references = references
        self.limits = limits
        self.extensions = extensions
        tree.reset()
        text.removeAll(keepingCapacity: true)
        lineScratchStart.removeAll(keepingCapacity: true)
        lineSourceStart.removeAll(keepingCapacity: true)
        delimiters.removeAll(keepingCapacity: true)
        brackets.removeAll(keepingCapacity: true)
        delimiterTop = -1
        position = 0
        work = 0
        droppedBackslashes.removeAll(keepingCapacity: true)
        for index in backticksExhausted.indices { backticksExhausted[index] = false }
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
        while position < text.count { parseInline() }
        processEmphasis(bottom: -1)
        if extensions.contains(.autolinks) { autolinkBareLinks() }
        let run = inlines.count
        serialize(into: &inlines)
        inlines.append(Slot.make(.marker, .runEnd, payload: 0, low: 0))
        return run
    }

    /// The source offset of the byte at `index` in the joined text.
    func sourceOffset(_ index: Int) -> Int {
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

    private static let special: [Bool] = {
        var table = [Bool](repeating: false, count: 256)
        for byte in "\n\\`*_~[]!<&".utf8 { table[Int(byte)] = true }
        return table
    }()

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

    private mutating func parseInline() {
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
            case 0x3C: angle()
            case 0x26: entity()
            default: plain()
        }
    }

    /// Plain text up to the next byte that can start something.
    private mutating func plain() {
        let start = position
        position += 1
        while position < text.count, !Self.special[Int(text[position])] { position += 1 }
        appendText(start, position)
    }

    private mutating func newline() {
        // Spaces before the line ending: two or more make a hard break, fewer a soft one, and either way they are not text.
        var spaces = 0
        let last = tree.nodes[0].lastChild
        if last >= 0, tree.nodes[Int(last)].kind == .text, tree.nodes[Int(last)].payload == 0 {
            let node = tree.nodes[Int(last)]
            var end = node.start + node.length
            while end > node.start, source[end - 1] == 0x20 {
                end -= 1
                spaces += 1
            }
            tree.nodes[Int(last)].length = end - node.start
        }
        tree.append(InlineNode(kind: spaces >= 2 ? .hardBreak : .softBreak))
        position += 1
        while position < text.count, text[position] == 0x20 || text[position] == 0x09 { position += 1 }
    }

    private mutating func backslash() {
        let next = position + 1 < text.count ? text[position + 1] : 0
        if next == 0x0A {
            tree.append(InlineNode(kind: .hardBreak))
            position += 2
            while position < text.count, text[position] == 0x20 || text[position] == 0x09 { position += 1 }
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
