extension MarkdownParser {
    /// Parses one line, `source[start ..< end]`, without its ending: cmark's `process_line`, writing slots as blocks open and close.
    mutating func processLine(_ start: Int, _ end: Int) {
        state.lineNumber += 1
        state.offset = start
        state.column = 0
        state.partiallyConsumedTab = false
        guard let lastMatched = matchOpenBlocks(end) else { return }
        var container = lastMatched
        startNewBlocks(&container, end)
        addText(container: container, lastMatched: lastMatched, end)
    }

    /// Walks the open blocks from the outermost and lets each take its prefix of the line. Returns the index of the last one that matched, or nil if the
    /// line is spent (it closed a code fence).
    private mutating func matchOpenBlocks(_ end: Int) -> Int? {
        var lastMatched = 0
        var index = 1
        while index < state.open.count {
            findFirstNonspace(end)
            let block = state.open[index]
            var matched = true
            switch block.kind {
                case .blockQuote:
                    if state.indent <= 3, peek(state.firstNonspace, end) == UInt8(ascii: ">") {
                        advance(state.firstNonspace + 1 - state.offset, columns: false, end)
                        if BlockScanner.isSpaceOrTab(peek(state.offset, end)) { advance(1, columns: true, end) }
                    } else {
                        matched = false
                    }
                case .item:
                    if state.indent >= block.markerOffset + block.padding {
                        advance(block.markerOffset + block.padding, columns: true, end)
                    } else if state.blank, block.hasChild {
                        advance(state.firstNonspace - state.offset, columns: false, end)
                    } else {
                        matched = false
                    }
                case .fencedCode:
                    if state.indent <= 3, peek(state.firstNonspace, end) == block.fenceCharacter,
                        let length = BlockScanner.codeFenceClosing(
                            source, state.firstNonspace, end, character: block.fenceCharacter),
                        length >= block.fenceLength
                    {
                        advance(end - state.offset, columns: false, end)
                        closeAbove(index - 1)
                        return nil
                    }
                    var skip = block.fenceOffset
                    while skip > 0, BlockScanner.isSpaceOrTab(peek(state.offset, end)) {
                        advance(1, columns: true, end)
                        skip -= 1
                    }
                case .indentedCode:
                    if state.indent >= 4 {
                        advance(4, columns: true, end)
                    } else if state.blank {
                        advance(state.firstNonspace - state.offset, columns: false, end)
                    } else {
                        matched = false
                    }
                case .htmlBlock:
                    if block.htmlCondition >= 6 && state.blank { matched = false }
                case .paragraph:
                    if state.blank { matched = false }
                case .heading, .thematicBreak:
                    matched = false
                case .list, .document:
                    break
            }
            if !matched { break }
            lastMatched = index
            index += 1
        }
        return lastMatched
    }
}
