internal import AemiFrontMatter

/// The edit that reads only its own region (ADR-0003, phase B). Every early `return nil` leaves the document as it was, except that the bytes may be in
/// `source` (`spliced`): the whole parse that follows takes them from there.
extension MarkdownEditor {
    private static let slots = BlockIndex.slotsPerBlock

    private var blockCount: Int { parser.topIndex.count / Self.slots }

    private func start(of ordinal: Int) -> Int { BlockIndex.start(parser.topIndex[ordinal * Self.slots]) }

    private func end(of ordinal: Int) -> Int { BlockIndex.end(parser.topIndex[ordinal * Self.slots]) }

    private func slot(of ordinal: Int) -> Int {
        ordinal < blockCount ? Int(parser.topIndex[ordinal * Self.slots + 2]) : parser.blocks.count
    }

    /// The first ordinal whose block starts at or after `offset`; `blockCount` if none does.
    private func firstBlock(startingAtOrAfter offset: Int) -> Int {
        var low = 0
        var high = blockCount
        while low < high {
            let middle = (low + high) / 2
            if start(of: middle) < offset { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The start of the second line of the block at `ordinal`, or the end of its first line if it has one line.
    private mutating func secondLineStart(of ordinal: Int) -> Int {
        let first = start(of: ordinal)
        let end = ByteScan.firstIndex(inSet: ByteScan.lineEndings, in: parser.source, from: first)
        return parser.lineEndOffset(after: end)
    }

    /// Whether `offset` starts a line of the new source (a carriage return and a line feed are one ending).
    private func startsLine(_ offset: Int) -> Bool {
        let source = parser.source
        if offset == 0 { return true }
        guard offset <= source.count else { return false }
        switch source[offset - 1] {
            case 0x0A: return true
            case 0x0D: return offset == source.count || source[offset] != 0x0A
            default: return false
        }
    }

    /// The index on the inline tape of the first run at or after slot `slot` of the block tape.
    private func inlineIndex(atOrAfter slot: Int, before limit: Int? = nil) -> Int? {
        var index = slot
        let end = Swift.min(limit ?? parser.blocks.count, parser.blocks.count)
        while index < end {
            let value = parser.blocks[index]
            if Slot.shape(value) == .leafBlock { return Slot.low(value) }
            index += 1
        }
        return limit == nil ? parser.inlines.count : nil
    }

    /// Whether `]:`, which every link reference definition and footnote definition has, stands in the three runs of bytes read as one.
    private func hasDefinitionMarker(_ first: ArraySlice<UInt8>, _ second: [UInt8], _ third: ArraySlice<UInt8>) -> Bool
    {
        var previous: UInt8 = 0
        func scan(_ run: some Sequence<UInt8>) -> Bool {
            for byte in run {
                if byte == UInt8(ascii: ":"), previous == UInt8(ascii: "]") { return true }
                previous = byte
            }
            return false
        }
        return scan(first) || scan(second) || scan(third)
    }

    /// Does the edit by reading only its region, or returns nil.
    /// How far into the source an edit may change the head (``MarkdownExtensions/frontMatter``): to the body's start when there is
    /// one; past its content's start by the bound when an opening fence was seen; the first line otherwise, where one may be written.
    private var headReach: Int {
        if let head = parser.head?.state.found { return head.bodyStart }
        if let contentStart = parser.head?.state.contentStart { return contentStart + limits.maxFrontMatterBytes + 1 }
        var end = 0
        while end < parser.source.count, parser.source[end] != 0x0A, parser.source[end] != 0x0D { end += 1 }
        return end + 1
    }

    /// The head is decided from the start of the document. An edit inside its content re-reads it alone, in a region from the start
    /// (the head it stays inside); one out of its reach reads its region (`.some(nil)`); any other may open, close or change the
    /// head, and parses whole (nil).
    private func headHolding(_ edit: Range<Int>) -> FrontMatter?? {
        guard parser.extensions.contains(.frontMatter), edit.lowerBound <= headReach else { return .some(nil) }
        guard let head = parser.head?.state.found, edit.lowerBound >= head.content.lowerBound,
            edit.upperBound <= head.content.upperBound
        else { return nil }
        return head
    }

    /// Whether a head re-read ends where the old one did, moved by the edit, so the body's bytes are the same; true without one.
    private func regionKeepsHead(_ oldHead: FrontMatter?, delta: Int) -> Bool {
        guard let oldHead else { return true }
        guard let newHead = region.head?.state.found else { return false }
        return newHead.format == oldHead.format && newHead.bodyStart == oldHead.bodyStart + delta
    }

    mutating func resync(_ range: Range<Int>, with bytes: [UInt8]) -> MarkdownChange? {
        let oldCount = parser.source.count
        let delta = bytes.count - range.count
        let lo = range.lowerBound
        let hi = range.upperBound
        guard parser.isFinished, parser.diagnostics.isEmpty, !parser.spliced,
            oldCount + delta <= limits.maxDocumentBytes
        else { return nil }
        guard let oldHead = headHolding(lo ..< hi) else { return nil }

        // Where to restart: the gap before the block that holds the edit's line, or before the block above it when the edit is on the block's first line.
        var editOffset = lo
        if lo > 0, lo < oldCount, parser.source[lo - 1] == 0x0D, parser.source[lo] == 0x0A { editOffset = lo - 1 }
        let editLine = parser.lineStartOffset(before: editOffset)
        let after = firstBlock(startingAtOrAfter: editLine + 1)  // blocks that start after the edit's line
        var first = after - 1  // the last block that starts at or before it
        // A line can change the block above it only from the block's first two lines: a setext underline or a table's delimiter row reads the line before.
        if first >= 0, editLine <= secondLineStart(of: first) { first -= 1 }
        first = oldHead == nil ? Swift.max(first, 0) : 0
        let restart = first == 0 ? 0 : parser.lineEndOffset(after: end(of: first - 1))
        if restart == 0, oldHead == nil, parser.head?.state.found != nil { return nil }

        // The bytes go in place now; the old ones are kept for the check below.
        removedBytes.removeAll(keepingCapacity: true)
        removedBytes.append(contentsOf: parser.source[range])
        parser.source.replaceSubrange(range, with: bytes)
        parser.spliced = true
        if restart > 0, parser.source[restart - 1] == 0x0D, restart < parser.source.count,
            parser.source[restart] == 0x0A
        {
            return nil
        }
        let referencesMoved = parser.references.shiftOffsets(from: hi, by: delta)
        let attempts = parser.references.insertAttempts

        // Read forward from the restart to the first old block start that the new text starts a block at too.
        region.beginRegion(of: parser.source, references: parser.references, at: restart)
        var resynced: Int?
        var candidate = firstBlock(startingAtOrAfter: hi)
        while candidate < blockCount {
            let boundary = start(of: candidate) + delta
            if startsLine(boundary), boundary >= region.lineStart {
                region.parseLines(upTo: boundary)
                if region.lineStart == boundary, region.startsTopLevelBlock(at: boundary) {
                    resynced = candidate
                    break
                }
            }
            candidate += 1
        }
        let oldEnd = resynced.map { start(of: $0) } ?? oldCount
        let newEnd = oldEnd + delta
        if let resynced {
            region.endRegion(at: start(of: resynced) + delta)
        } else {
            region.endRegionAtEndOfSource()
        }
        defer {
            region.source = []
            region.references = ReferenceTable()
        }
        guard region.diagnostics.isEmpty, region.references.insertAttempts == attempts,
            regionKeepsHead(oldHead, delta: delta)
        else { return nil }
        guard
            !hasDefinitionMarker(
                parser.source[restart ..< lo],
                removedBytes,
                parser.source[(lo + bytes.count) ..< newEnd]
            )
        else { return nil }

        let last = resynced ?? blockCount
        Self.collectHashes(into: &oldWindow, of: parser, from: first, count: last - first)
        newWindow.removeAll(keepingCapacity: true)
        for block in region.document().topLevelBlocks { newWindow.append(block.contentHash) }
        let result = change(first: first, replaced: range, insertedBytes: bytes.count)
        splice(first ..< last, delta: delta, threshold: hi, shiftPrefixLinks: referencesMoved)
        if oldHead != nil { (parser.head, parser.headBodyStart) = (region.head, region.headBodyStart) }
        parser.spliced = false
        parser.lineStart = parser.source.count
        parser.scanPosition = parser.source.count
        parser.scannedUpTo = parser.source.count
        return result
    }

    /// The pair on the stamp tape of the first leaf at or after `slot` of the block tape; the number of pairs if none.
    private func firstStamp(atOrAfter slot: Int) -> Int {
        var low = 0
        var high = parser.stamps.count / 2
        while low < high {
            let middle = (low + high) / 2
            if Int(parser.stamps[middle * 2]) < slot { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Puts the region's tapes in place of the old blocks `blocks`, and moves everything after them.
    private mutating func splice(_ blocks: Range<Int>, delta: Int, threshold: Int, shiftPrefixLinks: Bool) {
        let from = slot(of: blocks.lowerBound)
        let to = slot(of: blocks.upperBound)
        let inlineTo = inlineIndex(atOrAfter: to) ?? parser.inlines.count
        let inlineFrom = inlineIndex(atOrAfter: from, before: to) ?? inlineTo
        let newSlots = region.blocks.count
        let newInlines = region.inlines.count
        let slotShift = newSlots - (to - from)
        let inlineShift = newInlines - (inlineTo - inlineFrom)

        // What the region wrote starts at zero: its indices move to where it goes.
        region.blocks.shift(from: 0, TapeShift(container: from, leaf: inlineFrom))
        region.inlines.shift(from: 0, TapeShift(container: inlineFrom))
        if shiftPrefixLinks, delta != 0 {
            parser.inlines.shift(from: 0, to: inlineFrom, TapeShift(range: delta, rangesFrom: threshold))
        }
        let tailInlines = TapeShift(container: inlineShift, range: delta, rangesFrom: threshold)
        parser.inlines.replace(inlineFrom ..< inlineTo, with: region.inlines.committedSlots, tailShift: tailInlines)
        parser.blocks.replace(
            from ..< to,
            with: region.blocks.committedSlots,
            tailShift: TapeShift(container: slotShift, leaf: inlineShift, range: delta, rangesFrom: threshold)
        )

        // The index: the region's entries take the place of the old ones, their block slots moved to where they go; the later entries move with the edit.
        region.topIndex.shiftEntries(
            from: 0,
            stride: Self.slots,
            packedAt: nil,
            packedDelta: 0,
            slotAt: 2,
            slotDelta: from
        )
        let freshIndex = region.topIndex.committedSlots
        parser.topIndex.replace(
            blocks.lowerBound * Self.slots ..< blocks.upperBound * Self.slots,
            with: freshIndex,
            tailShift: TapeShift()
        )
        parser.topIndex.shiftEntries(
            from: blocks.lowerBound * Self.slots + freshIndex.count,
            stride: Self.slots,
            packedAt: 0,
            packedDelta: delta,
            slotAt: 2,
            slotDelta: slotShift
        )

        // The stamps: those of the old blocks go, the region's come, the later ones move with their blocks (a pair is a slot and a stamp).
        region.stamps.shiftEntries(from: 0, stride: 2, packedAt: nil, packedDelta: 0, slotAt: 0, slotDelta: from)
        let freshStamps = region.stamps.committedSlots
        let first = firstStamp(atOrAfter: from)
        let last = firstStamp(atOrAfter: to)
        parser.stamps.replace(first * 2 ..< last * 2, with: freshStamps, tailShift: TapeShift())
        parser.stamps.shiftEntries(
            from: first * 2 + freshStamps.count,
            stride: 2,
            packedAt: nil,
            packedDelta: 0,
            slotAt: 0,
            slotDelta: slotShift
        )
    }
}
