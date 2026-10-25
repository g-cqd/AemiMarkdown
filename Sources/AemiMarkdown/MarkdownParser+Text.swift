extension MarkdownParser {
    /// cmark's `add_text_to_container`: what is left of the line goes to the innermost block that takes text, and the blocks the line did not continue close.
    mutating func addText(container: Int, lastMatched: Int, _ end: Int) {
        findFirstNonspace(end)
        let blank = state.blank
        // A blank line ends the container's last child, which is still open if the line did not continue it.
        if blank, state.open[container].hasChild {
            if container + 1 < state.open.count {
                state.open[container + 1].lastLineBlank = true
            } else {
                state.open[container].childSelfBlank = true
            }
        }
        let kind = state.open[container].kind
        let countsAsBlank =
            blank && kind != .blockQuote && kind != .heading && kind != .thematicBreak && kind != .fencedCode
            && !(kind == .item && !state.open[container].hasChild
                && state.open[container].startLine == state.lineNumber)
        state.open[container].lastLineBlank = countsAsBlank
        for ancestor in 0 ..< container { state.open[ancestor].lastLineBlank = false }

        let tip = state.open.count - 1
        if container == lastMatched, tip != lastMatched, !blank, state.open[tip].kind == .paragraph {
            // A lazy continuation: the line continues a paragraph although some of its containers did not match.
            addLeafLine(to: tip, end)
            return
        }
        closeAbove(container)
        switch kind {
            case .fencedCode where state.open[container].startLine == state.lineNumber:
                break  // the opening fence line holds the info string, which `startNewBlocks` recorded
            case .indentedCode, .fencedCode:
                addCodeLine(end)
            case .htmlBlock:
                addCodeLine(end)
                if (1 ... 5).contains(state.open[container].htmlCondition),
                    HTMLBlockScanner.ends(state.open[container].htmlCondition, source, state.offset, end)
                {
                    closeAbove(container - 1)
                }
            case _ where blank:
                break
            case .heading, .paragraph:
                addLeafLine(to: container, end)
            default:
                // The first block of a list item may start with a task list marker.
                let firstInItem = kind == .item && !state.open[container].hasChild
                let firstInQuote = kind == .blockQuote && !state.open[container].hasChild
                let paragraph = addChild(
                    .paragraph, to: container, slot: Slot.make(.leafBlock, .paragraph, payload: 0, low: 0))
                state.open[paragraph].taskCandidate = firstInItem && extensions.contains(.taskLists)
                state.open[paragraph].alertCandidate = firstInQuote && extensions.contains(.alerts)
                addLeafLine(to: paragraph, end)
        }
    }

    /// A line of a paragraph or a heading: the rest of the line from its first non-blank byte.
    private mutating func addLeafLine(to index: Int, _ end: Int) {
        var range = state.firstNonspace ..< end
        if state.open[index].kind == .heading, state.open[index].lineCount == 0 { range = trimmedHeading(range) }
        if state.open[index].lineCount == 0 { state.open[index].firstLine = state.lineRanges.count }
        state.lineRanges.append(range)
        state.open[index].lineCount += 1
    }

    /// The content of an ATX heading: without the spaces after the `#`s, the spaces before the end, and an optional closing sequence of `#`s.
    private func trimmedHeading(_ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, BlockScanner.isSpaceOrTab(source[lower]) { lower += 1 }
        while upper > lower, BlockScanner.isSpaceOrTab(source[upper - 1]) { upper -= 1 }
        var hashes = upper
        while hashes > lower, source[hashes - 1] == UInt8(ascii: "#") { hashes -= 1 }
        if hashes < upper, hashes == lower || BlockScanner.isSpaceOrTab(source[hashes - 1]) {
            upper = hashes
            while upper > lower, BlockScanner.isSpaceOrTab(source[upper - 1]) { upper -= 1 }
        }
        return lower ..< upper
    }

    /// A line of a code or HTML block, from the cursor. A tab the cursor is inside of leaves spaces first.
    private mutating func addCodeLine(_ end: Int) {
        var from = state.offset
        if state.partiallyConsumedTab {
            from += 1
            let spaces = Self.tabStop - state.column % Self.tabStop
            blocks.append(Slot.make(.marker, .virtualSpaces, payload: 0, low: spaces))
        }
        from = Swift.min(from, end)
        blocks.append(Slot.make(.range, .codeLine, payload: end - from, low: from))
    }
}
