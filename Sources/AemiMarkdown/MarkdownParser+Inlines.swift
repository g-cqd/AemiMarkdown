extension MarkdownParser {
    /// Parses the inlines of every leaf block that is waiting, writes their runs on the inline tape, and points each leaf at its run.
    ///
    /// For now each line is one text run and a line ending is a soft break; the inline parser replaces this.
    mutating func parsePendingInlines() {
        for leaf in state.pending {
            let run = inlines.count
            for line in 0 ..< leaf.lineCount {
                var range = state.lineRanges[leaf.firstLine + line]
                if line == leaf.lineCount - 1 {
                    while range.upperBound > range.lowerBound, BlockScanner.isSpaceOrTab(source[range.upperBound - 1]) {
                        range = range.lowerBound ..< (range.upperBound - 1)
                    }
                }
                if line > 0 { inlines.append(Slot.make(.marker, .softBreak, payload: 0, low: 0)) }
                if !range.isEmpty {
                    inlines.append(Slot.make(.range, .text, payload: range.count, low: range.lowerBound))
                }
            }
            inlines.append(Slot.make(.marker, .runEnd, payload: 0, low: 0))
            blocks[leaf.slot] = Slot.withLow(blocks[leaf.slot], run)
        }
        state.pending.removeAll(keepingCapacity: true)
    }
}
