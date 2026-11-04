import Testing

@testable import AemiMarkdown

/// The cells of a table row are found with a SIMD scan for pipes and backslashes (ask roadmap 0205, E2); the scalar loop it replaced is the oracle.
@Suite("Table cells are split as the scalar loop split them")
struct TableCellSplitTests {
    /// The loop the SIMD scan replaced, byte at a time.
    private func reference(_ row: [UInt8]) -> [Range<Int>] {
        var cells: [Range<Int>] = []
        func blank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }
        var index = 0
        var upper = row.count
        while upper > index, blank(row[upper - 1]) { upper -= 1 }
        while index < upper, blank(row[index]) { index += 1 }
        if index < upper, row[index] == UInt8(ascii: "|") { index += 1 }
        while index < upper {
            var scan = index
            while scan < upper, row[scan] != UInt8(ascii: "|") { scan += row[scan] == UInt8(ascii: "\\") ? 2 : 1 }
            scan = Swift.min(scan, upper)
            var start = index
            var end = scan
            while start < end, blank(row[start]) { start += 1 }
            while end > start, blank(row[end - 1]) { end -= 1 }
            cells.append(start ..< end)
            index = scan + 1
        }
        return cells
    }

    private func cells(_ row: [UInt8], around prefix: Int = 0) -> [Range<Int>] {
        var parser = MarkdownParser()
        // Pipes before and after the row must not be seen.
        let padding = [UInt8](repeating: UInt8(ascii: "|"), count: prefix)
        let source = padding + row + padding
        parser.source = ContiguousArray(source)
        parser.splitCells(prefix ..< (prefix + row.count))
        return parser.state.cells.map { ($0.lowerBound - prefix) ..< ($0.upperBound - prefix) }
    }

    @Test func `rows with every placement of pipes, backslashes and white space, up to 9 bytes`() {
        let alphabet: [UInt8] = Array("|\\ a\t".utf8)
        var row: [UInt8] = []
        func visit(_ length: Int) {
            if row.count == length {
                #expect(cells(row) == reference(row), "\(String(decoding: row, as: UTF8.self).debugDescription)")
                return
            }
            for byte in alphabet {
                row.append(byte)
                visit(length)
                row.removeLast()
            }
        }
        for length in 0 ... 7 { visit(length) }
    }

    @Test func `long random rows, across the widths the scan works in, with bytes around them that must not be seen`() {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next() -> Int {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Int(truncatingIfNeeded: state >> 1)
        }
        let alphabet: [UInt8] = Array("|\\ aaaaaaaaaa\t".utf8)
        for _ in 0 ..< 20000 {
            let row = (0 ..< next() % 150).map { _ in alphabet[next() % alphabet.count] }
            #expect(
                cells(row, around: next() % 3 * 5) == reference(row),
                "\(String(decoding: row, as: UTF8.self).debugDescription)"
            )
        }
    }
}
