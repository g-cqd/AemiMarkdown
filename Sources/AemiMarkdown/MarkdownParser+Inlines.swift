extension MarkdownParser {
    /// Keeps an incremental inline parse of an unfinished trailing line that runs without line breaks for many bytes.
    mutating func updateIncrementalParagraph() {
        guard !isFinished, state.open.count <= 2 else {
            openParagraphParser = nil
            openParagraphParsedUpTo = 0
            return
        }
        let trailingCount = source.count - lineStart
        guard trailingCount >= 512, trailingCount <= limits.maxLeafBytes else {
            openParagraphParser = nil
            openParagraphParsedUpTo = 0
            return
        }
        if openParagraphParser == nil || openParagraphParsedUpTo < lineStart {
            var parser = InlineParser()
            parser.source = source
            parser.limits = limits
            parser.extensions = extensions
            parser.tree.reset()
            parser.lineScratchStart = [0]
            parser.lineSourceStart = [lineStart]
            parser.workLimit = limits.maxInlineWorkPerByte * (trailingCount + 16)
            parser.text.reserveCapacity(trailingCount)
            openParagraphParser = parser
            openParagraphParsedUpTo = lineStart
        }
        guard var parser = openParagraphParser else { return }
        parser.source = source
        if source.count > openParagraphParsedUpTo {
            parser.text.append(contentsOf: source[openParagraphParsedUpTo ..< source.count])
            parser.workLimit = limits.maxInlineWorkPerByte * (parser.text.count + 16)
            while parser.position < parser.text.count {
                parser.parseInline()
            }
            openParagraphParsedUpTo = source.count
            openParagraphParser = parser
        }
    }

    /// Parses the inlines of every leaf block that is waiting, writes their runs on the inline tape, and points each leaf at its run.
    mutating func parsePendingInlines() {
        for leaf in state.pending {
            let lines = state.lineRanges[leaf.firstLine ..< (leaf.firstLine + leaf.lineCount)]
            inlineParser.diagnostics = []
            let run = inlines.count
            if var parser = openParagraphParser, leaf.slot == blocks.count - 1, lines.count == 1,
                parser.lineSourceStart[0] == lines[lines.startIndex].lowerBound
            {
                parser.processEmphasis(bottom: -1)
                if parser.extensions.contains(.autolinks), parser.text.count <= parser.limits.maxLeafBytes,
                    parser.mayHoldBareLink()
                {
                    parser.autolinkBareLinks()
                }
                parser.serialize(into: &inlines)
                inlines.append(Slot.make(.marker, .runEnd, payload: 0, low: 0))
                openParagraphParser = nil
                openParagraphParsedUpTo = 0
            } else {
                _ = inlineParser.parse(
                    source: source, lines: lines, references: references, limits: limits, extensions: extensions,
                    isTableCell: Slot.kind(blocks[leaf.slot]) == .tableCell, isTaskCandidate: leaf.taskCandidate,
                    into: &inlines)
            }
            diagnostics.formUnion(inlineParser.diagnostics)
            inlineSteps += inlineParser.work
            blocks[leaf.slot] = Slot.withLow(blocks[leaf.slot], run)
        }
        state.pending.removeAll(keepingCapacity: true)
    }
}
