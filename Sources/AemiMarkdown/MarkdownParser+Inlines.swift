extension MarkdownParser {
    /// Parses the inlines of every leaf block that is waiting, writes their runs on the inline tape, and points each leaf at its run.
    mutating func parsePendingInlines() {
        for leaf in state.pending {
            let lines = state.lineRanges[leaf.firstLine ..< (leaf.firstLine + leaf.lineCount)]
            inlineParser.diagnostics = []
            let run = inlineParser.parse(
                source: source, lines: lines, references: references, limits: limits, extensions: extensions,
                isTableCell: Slot.kind(blocks[leaf.slot]) == .tableCell, isTaskCandidate: leaf.taskCandidate,
                into: &inlines)
            diagnostics.formUnion(inlineParser.diagnostics)
            inlineSteps += inlineParser.work
            blocks[leaf.slot] = Slot.withLow(blocks[leaf.slot], run)
        }
        state.pending.removeAll(keepingCapacity: true)
    }
}
