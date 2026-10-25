extension MarkdownParser {
    private static let alignmentBits: UInt128 = 0b11

    /// GitHub tables: starts one when the rest of the line is a delimiter row under a paragraph whose last line is the header, and adds a row when the
    /// open block is a table. True if the line was used.
    mutating func tryTable(container: inout Int, _ end: Int) -> Bool {
        guard extensions.contains(.tables), state.firstNonspace < end else { return false }
        switch state.open[container].kind {
            case .table: return addTableRow(container: container, end)
            case .paragraph: return state.indent < 4 && startTable(container: &container, end)
            default: return false
        }
    }

    /// Splits `source[range]` into trimmed cells in `state.cells`: a leading and a trailing pipe are optional, and `\|` does not divide.
    private mutating func splitCells(_ range: Range<Int>) {
        state.cells.removeAll(keepingCapacity: true)
        var index = range.lowerBound
        var upper = range.upperBound
        while upper > index, BlockScanner.isSpaceOrTab(source[upper - 1]) { upper -= 1 }
        while index < upper, BlockScanner.isSpaceOrTab(source[index]) { index += 1 }
        if index < upper, source[index] == UInt8(ascii: "|") { index += 1 }
        while index < upper {
            var scan = index
            while scan < upper, source[scan] != UInt8(ascii: "|") { scan += source[scan] == UInt8(ascii: "\\") ? 2 : 1 }
            scan = Swift.min(scan, upper)
            var cellStart = index
            var cellEnd = scan
            while cellStart < cellEnd, BlockScanner.isSpaceOrTab(source[cellStart]) { cellStart += 1 }
            while cellEnd > cellStart, BlockScanner.isSpaceOrTab(source[cellEnd - 1]) { cellEnd -= 1 }
            state.cells.append(cellStart ..< cellEnd)
            index = scan + 1
        }
    }

    /// The alignments in a delimiter row, two bits a column (1 left, 2 center, 3 right), and the number of columns; nil if the line is not one.
    private mutating func delimiterRow(_ range: Range<Int>) -> (alignments: UInt128, columns: Int)? {
        splitCells(range)
        guard !state.cells.isEmpty, state.cells.count <= limits.maxTableColumns else { return nil }
        var alignments: UInt128 = 0
        for (column, cell) in state.cells.enumerated() {
            var i = cell.lowerBound
            let left = i < cell.upperBound && source[i] == UInt8(ascii: ":")
            if left { i += 1 }
            let dashes = i
            while i < cell.upperBound, source[i] == UInt8(ascii: "-") { i += 1 }
            guard i > dashes else { return nil }
            let right = i < cell.upperBound && source[i] == UInt8(ascii: ":")
            if right { i += 1 }
            guard i == cell.upperBound else { return nil }
            let alignment: UInt128 = left && right ? 2 : (right ? 3 : (left ? 1 : 0))
            alignments |= alignment << UInt128(column * 2)
        }
        return (alignments, state.cells.count)
    }

    /// Opens a table if the line is a delimiter row, the paragraph's last line has as many cells, and no limit is passed.
    private mutating func startTable(container: inout Int, _ end: Int) -> Bool {
        let paragraph = state.open[container]
        guard paragraph.lineCount > 0, let delimiter = delimiterRow(state.firstNonspace ..< end) else { return false }
        let header = state.lineRanges[paragraph.firstLine + paragraph.lineCount - 1]
        splitCells(header)
        guard state.cells.count == delimiter.columns else { return false }
        // The lines above the header stay a paragraph; a paragraph that is only the header becomes the table.
        if paragraph.lineCount > 1 {
            state.open[container].lineCount -= 1
            closeAbove(container - 1)
        } else {
            state.open.removeLast()
            blocks.removeLast()
        }
        let table = addChild(
            .table, to: container - 1, slot: Slot.make(.container, .table, payload: delimiter.columns, low: 0))
        state.open[table].columns = delimiter.columns
        state.open[table].alignments = delimiter.alignments
        appendRow(header: true, table: table, cells: header)
        advance(end - state.offset, columns: false, end)
        container = table
        return true
    }

    private mutating func addTableRow(container: Int, _ end: Int) -> Bool {
        let range = state.firstNonspace ..< end
        splitCells(range)
        guard !state.cells.isEmpty else { return false }
        appendRow(header: false, table: container, cells: range)
        advance(end - state.offset, columns: false, end)
        return true
    }

    /// Writes a row of the table at `table`, from the line `range`. Missing cells are empty and extra ones are dropped.
    private mutating func appendRow(header: Bool, table: Int, cells line: Range<Int>) {
        splitCells(line)
        let columns = state.open[table].columns
        let alignments = state.open[table].alignments
        let row = appendBlock(Slot.make(.container, .tableRow, payload: header ? 1 : 0, low: 0))
        for column in 0 ..< columns {
            let range = column < state.cells.count ? state.cells[column] : line.upperBound ..< line.upperBound
            let alignment = Int((alignments >> UInt128(column * 2)) & Self.alignmentBits)
            let slot = appendBlock(Slot.make(.leafBlock, .tableCell, payload: alignment, low: 0))
            state.pending.append(.init(slot: slot, firstLine: state.lineRanges.count, lineCount: 1))
            state.lineRanges.append(range)
        }
        blocks[row] = Slot.withLow(blocks[row], blocks.count)
        state.open[table].hasChild = true
    }
}
