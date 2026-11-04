internal import AemiKernel

/// The index of top-level blocks (ADR-0003): for each block that closes under the document, three slots on a tape of its own,
/// committed with the block tape so that a snapshot shares the closed part.
///
/// | slot | holds |
/// |---|---|
/// | 0 | the first source byte (low 32 bits) and one past the last (high 32 bits) |
/// | 1 | the content hash: wyhash of those bytes, seeded with the block's kind |
/// | 2 | the block's first slot on the block tape |
///
/// A block's source runs from the start of its first line to the end of its last line that has text, without that line's ending: its closing fence,
/// marker lines and the lines a lazy continuation took are inside it, the blank lines after it and its last line ending are not. White space at the end of
/// the last line stays: it is a code line's content.
enum BlockIndex {
    static let slotsPerBlock = 3

    @inline(__always)
    static func pack(start: Int, end: Int) -> UInt64 {
        UInt64(truncatingIfNeeded: start) | UInt64(truncatingIfNeeded: end) << 32
    }

    @inline(__always)
    static func start(_ slot: UInt64) -> Int { Int(slot & 0xFFFF_FFFF) }

    @inline(__always)
    static func end(_ slot: UInt64) -> Int { Int(slot >> 32) }
}

extension MarkdownParser {
    /// Notes the top-level block that has just closed: its source range and its content hash. A paragraph made only of link reference definitions
    /// has left the tape and has no entry.
    mutating func recordTopLevel(_ block: BlockState.Open) {
        guard block.slot >= 0, block.slot < blocks.count else { return }
        let start = Swift.min(block.startOffset, source.count)
        let consumed = Swift.min(Swift.max(state.consumedEnd, start), source.count)
        // A block that ends in a fence or an HTML block that nothing closed owns the blank lines after its text: they are lines of it.
        let end = state.verbatimEnd == state.consumedEnd ? consumed : lastTextLineEnd(start: start, consumed: consumed)
        let seed = UInt64(Slot.kind(blocks[block.slot]).rawValue)
        let hash = source.withUnsafeBytes { raw -> UInt64 in
            // SAFETY: `start <= end <= source.count`, so the slice names bytes inside the buffer the closure is lent.
            unsafe WyHash.hash(UnsafeRawBufferPointer(rebasing: raw[start ..< end]), seed: seed)
        }
        topIndex.append(BlockIndex.pack(start: start, end: end))
        topIndex.append(hash)
        topIndex.append(UInt64(block.slot))
    }

    /// One past the last byte of the last line that has text in `source[start ..< consumed]`, not counting that line's ending.
    func lastTextLineEnd(start: Int, consumed: Int) -> Int {
        var end = consumed
        while end > start {
            if source[end - 1] == 0x0A {
                end -= 1
                if end > start, source[end - 1] == 0x0D { end -= 1 }
            } else if source[end - 1] == 0x0D {
                end -= 1
            }
            // The usual case: a byte of text ends the line, so the line is not blank and nothing needs scanning.
            if end > start {
                let last = source[end - 1]
                if last != 0x20, last != 0x09, last != 0x0A, last != 0x0D { return end }
            }
            var lineStart = end
            while lineStart > start, source[lineStart - 1] != 0x0A, source[lineStart - 1] != 0x0D { lineStart -= 1 }
            if !source[lineStart ..< end].allSatisfy(BlockScanner.isSpaceOrTab) { return end }
            end = lineStart
        }
        return end
    }

    /// The first byte of the line that holds the byte at `offset`.
    func lineStartOffset(before offset: Int) -> Int {
        var start = Swift.min(offset, source.count)
        while start > 0, source[start - 1] != 0x0A, source[start - 1] != 0x0D { start -= 1 }
        return start
    }

    /// Where the line that ends at `end` (without its ending) ends with its ending: past a line feed, a carriage return, or both.
    func lineEndOffset(after end: Int) -> Int {
        guard end < source.count else { return end }
        switch source[end] {
            case 0x0A: return end + 1
            case 0x0D: return end + 1 < source.count && source[end + 1] == 0x0A ? end + 2 : end + 1
            default: return end
        }
    }
}
