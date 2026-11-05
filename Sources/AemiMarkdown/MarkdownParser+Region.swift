internal import AemiKernels

/// Parsing a part of a document that was edited, in the coordinates of the whole (ADR-0003, phase B).
///
/// The part starts at a line where nothing is open, so a fresh parser reads it as the whole parse did, and it ends where a top-level block of the new
/// text starts at the place a top-level block of the old text started (shifted by the edit): from there on the lines and the state are the same, so the old
/// tapes are right again. Offsets in the slots are offsets into the whole source; indices on the tapes start at zero and are moved by the editor.
extension MarkdownParser {
    /// Starts reading `source` at `start`, a line start, with nothing open and the definitions of the whole document.
    mutating func beginRegion(of source: ContiguousArray<UInt8>, references: ReferenceTable, at start: Int) {
        self.source = []  // the last region's reference, so that `reset` does not keep and clear a shared array
        reset()
        self.source = source
        self.references = references
        // A region never holds the head: the editor parses whole when an edit is within reach of it.
        head = nil
        headBodyStart = 0
        lineStart = start
        scanPosition = start
        scannedUpTo = start
        state.consumedEnd = start
        state.lineStartOffset = start
    }

    /// Reads the complete lines up to `limit`, a line start at or before the end of the source.
    mutating func parseLines(upTo limit: Int) {
        defer { scan(upTo: lineStart) }
        var cursor = scanPosition
        while cursor < limit {
            cursor = ByteScan.firstIndex(inSet: ByteScan.lineEndings, in: source, from: cursor)
            guard cursor < limit else { break }
            guard source[cursor] == 0x0A else {
                // A carriage return, alone or before a line feed; the caller made sure `limit` does not fall between the two.
                processLines(start: lineStart, end: cursor)
                commitClosedBlocks()
                lineStart = cursor + 1 < source.count && source[cursor + 1] == 0x0A ? cursor + 2 : cursor + 1
                cursor = lineStart
                continue
            }
            processLines(start: lineStart, end: cursor)
            commitClosedBlocks()
            lineStart = cursor + 1
            cursor += 1
        }
        scanPosition = lineStart
    }

    /// Whether the line that starts at `boundary` starts a top-level block when it is read next. With nothing open that is a look at the line; otherwise the
    /// state is copied, the line is read on the copy, and this parser is left as it was. It does not look when the open blocks are large, so the cost of a look is bounded; a block it does not look at is
    /// not a place to stop.
    mutating func startsTopLevelBlock(at boundary: Int) -> Bool {
        if state.open.count == 1 {
            // Nothing is open, so any line with something in it starts a block: no copy of the state is needed.
            var index = boundary
            while index < source.count, BlockScanner.isSpaceOrTab(source[index]) { index += 1 }
            return index < source.count && source[index] != 0x0A && source[index] != 0x0D
        }
        guard blocks.tailCount <= 4096, state.lineRanges.count <= 4096, state.open.count <= 64 else { return false }
        var probe = self
        var end = ByteScan.firstIndex(inSet: ByteScan.lineEndings, in: source, from: boundary)
        end = Swift.min(end, boundary + limits.maxLineBytes)
        probe.processLine(boundary, end)
        return probe.state.open.count > 1 && probe.state.open[1].startOffset == boundary
    }

    /// Ends the region at `limit`, a line start before the end of the source: everything open closes, and the inline runs are parsed.
    mutating func endRegion(at limit: Int) {
        isFinished = true
        scan(upTo: limit)
        lineStart = limit
        closeAbove(0)
        parsePendingInlines()
        blocks.commit()
        topIndex.commit()
        inlines.commit()
        stamps.commit()
    }

    /// Reads the rest of the source and ends, as `append` and `finish` do for a whole document.
    mutating func endRegionAtEndOfSource() {
        processCompleteLines()
        updateIncrementalParagraph()
        finish()
    }
}
