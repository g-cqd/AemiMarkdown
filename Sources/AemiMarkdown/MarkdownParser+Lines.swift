internal import AemiKernels

extension MarkdownParser {
    /// Adds bytes to the document. Complete lines are parsed now; a partial last line waits for the rest of it.
    /// - Complexity: O(bytes.count), within the limits.
    public mutating func append(_ bytes: [UInt8]) {
        guard !isFinished, !bytes.isEmpty else { return }
        var bytes = bytes[...]
        let room = limits.maxDocumentBytes - source.count
        if bytes.count > room {
            diagnostics.insert(.documentSizeLimit)
            bytes = bytes.prefix(Swift.max(0, room))
        }
        source.append(contentsOf: bytes)
        processCompleteLines()
    }

    /// Ends the document: the last line, if it has no ending, is parsed, every open block closes, and every inline run is parsed.
    public mutating func finish() {
        close()
        blocks.commit()
        inlines.commit()
    }

    /// The document as it stands: closed blocks are final, and the open ones are drawn as if the input ended here. Parsing goes on afterwards.
    ///
    /// The cost is that of the open top-level block, not of the document: the closed part is shared, and the rest is parsed into a copy that is thrown away.
    /// A later `append` copies the closed part once if the snapshot is still alive, so a reader lets one go before it appends.
    /// - Note: a link reference definition in the open paragraph is not applied yet, and one that closed after a link does not reach it. A document
    ///   parsed whole (`parse(_:)`) applies every definition.
    public mutating func snapshot() -> MarkdownDocument {
        guard !isFinished else { return document() }
        // What has closed is final.
        parsePendingInlines()
        inlines.commit()
        if state.open.allSatisfy({ $0.lineCount == 0 }) { state.lineRanges.removeAll(keepingCapacity: true) }
        // The rest is parsed on a copy, which owns the inline parser's buffers while it works and hands them back.
        var provisional = self
        inlineParser = InlineParser()
        provisional.close()
        inlineParser = provisional.inlineParser
        return provisional.document()
    }

    /// Parses the last line, closes every open block and parses every inline run, without committing.
    private mutating func close() {
        guard !isFinished else { return }
        isFinished = true
        // A carriage return that waited for a line feed has none coming: it ends its line (docs/formal/LineSplitter.tla found this).
        if scanPosition < source.count, source[scanPosition] == 0x0D {
            processLines(start: lineStart, end: scanPosition)
            lineStart = scanPosition + 1
        }
        if lineStart < source.count { processLines(start: lineStart, end: source.count) }
        lineStart = source.count
        closeAbove(0)
        parsePendingInlines()
    }

    /// Notes control bytes and invalid UTF-8 in one line, which is complete, so no character is cut by a chunk boundary.
    private mutating func scan(_ range: Range<Int>) {
        guard !range.isEmpty else { return }
        let found = source.withUnsafeBufferPointer { buffer in unsafe Self.scanBytes(buffer, range) }
        diagnostics.formUnion(found)
    }

    /// SAFETY: `range` lies inside `buffer` (a caller passes a line of the source), so every pointer made below stays inside it, and each kernel call
    /// is given the count that remains after that pointer.
    @unsafe
    private static func scanBytes(_ buffer: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> MarkdownDiagnostics {
        guard let start = buffer.baseAddress else { return [] }
        let base = unsafe start + range.lowerBound
        var result: MarkdownDiagnostics = []
        if unsafe AemiKernels.firstInvalidUTF8(base: base, count: range.count) != range.count {
            result.insert(.invalidUTF8)
        }
        // Tab is a control byte Markdown uses, so the scan resumes after one. A line has no line ending in it.
        var index = 0
        while index < range.count {
            let offset = unsafe AemiKernels.indexOfControlOrAny(
                base: base + index, count: range.count - index, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F)
            let hit = index + offset
            if hit >= range.count { break }
            if unsafe base[hit] != 0x09 {
                result.insert(.controlBytes)
                break
            }
            index = hit + 1
        }
        return result
    }

    /// Parses each complete line from `from` on. A line ends at a line feed, a carriage return, or a carriage return and a line feed.
    private mutating func processCompleteLines() {
        var cursor = scanPosition
        while cursor < source.count {
            let byte = source[cursor]
            if byte == 0x0A {
                processLines(start: lineStart, end: cursor)
                commitClosedBlocks()
                lineStart = cursor + 1
            } else if byte == 0x0D {
                // A carriage return at the very end may be the first half of a line ending whose second half has not arrived.
                guard cursor + 1 < source.count else {
                    scanPosition = cursor
                    return
                }
                processLines(start: lineStart, end: cursor)
                commitClosedBlocks()
                lineStart = source[cursor + 1] == 0x0A ? cursor + 2 : cursor + 1
                cursor = lineStart
                continue
            }
            cursor += 1
        }
        scanPosition = cursor
    }

    /// Parses one line, cut into pieces of at most `maxLineBytes` so that no line is longer than the limit says.
    private mutating func processLines(start: Int, end: Int) {
        scan(start ..< end)
        var from = start
        while end - from > limits.maxLineBytes {
            diagnostics.insert(.lineLengthLimit)
            processLine(from, from + limits.maxLineBytes)
            from += limits.maxLineBytes
        }
        processLine(from, end)
    }

    /// A top-level block that has closed is final, and no later line can change it. Only the parser itself commits: a snapshot works on a copy and must
    /// write nothing to the tapes it shares (docs/formal/SnapshotProtocol.tla).
    private mutating func commitClosedBlocks() {
        if state.open.count == 1 { blocks.commit() }
    }
}
