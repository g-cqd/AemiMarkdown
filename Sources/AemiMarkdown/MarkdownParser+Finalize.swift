extension MarkdownParser {
    /// Closes the innermost open block: writes its end into its slot and settles what depends on its content.
    mutating func finalizeTop() {
        let block = state.open.removeLast()
        switch block.kind {
            case .document: break
            case .paragraph:
                resolveReferenceDefinitionsAtClose(block)
            case .heading:
                state.pending.append(.init(slot: block.slot, firstLine: block.firstLine, lineCount: block.lineCount))
            case .thematicBreak: break
            case .indentedCode:
                trimTrailingBlankCodeLines()
                blocks[block.slot] = Slot.withLow(blocks[block.slot], blocks.count)
            case .fencedCode, .htmlBlock, .blockQuote, .item, .table:
                blocks[block.slot] = Slot.withLow(blocks[block.slot], blocks.count)
            case .list:
                var slot = Slot.withLow(blocks[block.slot], blocks.count)
                if !block.loose { slot = Slot.withPayload(slot, Slot.payload(slot) | ListFlags.tight.rawValue) }
                blocks[block.slot] = slot
        }
        let parent = state.open.count - 1
        if parent >= 0 {
            state.open[parent].childSelfBlank = block.lastLineBlank
            state.open[parent].childInnerBlank = block.lastChildEndsBlank
            state.open[parent].childIsContainer = block.kind == .list || block.kind == .item
        }
    }

    /// An indented code block ends before the blank lines that follow its last line with text.
    private mutating func trimTrailingBlankCodeLines() {
        while let last = blocks.last, Slot.kind(last) == .codeLine || Slot.kind(last) == .virtualSpaces {
            if Slot.kind(last) == .codeLine {
                let start = Slot.low(last)
                let length = Slot.payload(last)
                guard source[start ..< (start + length)].allSatisfy(BlockScanner.isSpaceOrTab) else { break }
            }
            blocks.removeLast()
        }
    }
}
