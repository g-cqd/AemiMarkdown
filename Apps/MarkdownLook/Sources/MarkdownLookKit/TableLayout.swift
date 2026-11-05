/// How a table's columns are sized (ADR 0004): browsers lay columns out by their longest text and break short cells such as `UTF-8` or `30, p90` to make room for long ones. The writer
/// measures each cell as it writes it; at the end of the table a short column keeps its text on one line, a long column may wrap but never below its longest word, and the table sits in a
/// box that scrolls sideways when even that does not fit, instead of the page.
struct TableLayout {
    /// What one column holds: the longest cell and the longest word, in characters.
    struct Column {
        var longest = 0
        var longestWord = 0
    }

    /// The widest a column may be and still keep its text on one line, from the limits tried: the largest for which the table, its long columns counted at `flexibleShare`, fits the room.
    static let fitLimits = [60, 48, 40, 32, 24, 18]
    static let flexibleShare = 24
    /// What a table may take beside the text column, in characters: the window's reading width less margins.
    static let room = 110
    /// Past this many characters, a table is wider than the text column and takes the room beside it.
    static let wideAbove = 76
    /// The narrowest a long column is made, and the widest minimum it is given, in characters.
    static let flexibleFloor = 12
    static let flexibleCeiling = 28

    var columns: [Column] = []
    /// Where each cell's start tag ends its name (byte offset in the table's markup) and the column it is in.
    var cells: [(offset: Int, column: Int)] = []
    var column = 0
    var cellStart = 0
    var cellOffset = 0

    mutating func startCell(at offset: Int) { cellOffset = offset }

    /// Ends a cell whose markup is `markup[cellStart...]`.
    mutating func endCell(markup: String.UTF8View, from start: Int) {
        if column >= columns.count { columns.append(Column()) }
        finishCell(Self.measure(markup, from: start))
    }

    /// Ends a cell whose markup is `markup[start...]`, in the writer's byte buffer.
    mutating func endCell(bytes markup: [UInt8], from start: Int) {
        if column >= columns.count { columns.append(Column()) }
        finishCell(Self.measure(bytes: markup, from: start))
    }

    private mutating func finishCell(_ measured: (length: Int, word: Int)) {
        let (length, word) = measured
        columns[column].longest = Swift.max(columns[column].longest, length)
        columns[column].longestWord = Swift.max(columns[column].longestWord, word)
        cells.append((cellOffset, column))
        column += 1
    }

    /// The visible characters and the longest word of the markup from `start` on: tags are skipped and an entity counts as one character.
    static func measure(_ markup: String.UTF8View, from start: Int) -> (length: Int, word: Int) {
        measure(bytes: Array(markup.dropFirst(start)), from: 0)
    }

    static func measure(bytes markup: [UInt8], from start: Int) -> (length: Int, word: Int) {
        var length = 0
        var word = 0
        var current = 0
        var inTag = false
        var inEntity = false
        for byte in markup[start...] {
            if inTag {
                if byte == 0x3E { inTag = false }
                continue
            }
            if byte == 0x3C {
                inTag = true
                continue
            }
            if inEntity {
                if byte == 0x3B { inEntity = false }
                continue
            }
            if byte == 0x26 { inEntity = true }
            if byte & 0xC0 == 0x80 { continue }  // a continuation byte: the character was counted
            length += 1
            if byte == 0x20 || byte == 0x0A {
                current = 0
            } else {
                current += 1
                word = Swift.max(word, current)
            }
        }
        return (length, word)
    }

    /// Whether the table, as its columns are sized, is wider than the text column (about 70 characters): it then takes the room beside the column, up to the window, and scrolls only
    /// when that is not enough either.
    var isWide: Bool { estimate(fitLimit: fitLimit) > Self.wideAbove }

    private func estimate(fitLimit: Int) -> Int {
        columns.reduce(0) { total, column in
            total + width(of: column, fitLimit: fitLimit) + 3
        }
    }

    /// What a column takes, in characters: its longest cell if that stays on a line; else the share a long column is counted at, and never less than its longest word, which no wrapping narrows.
    private func width(of column: Column, fitLimit: Int) -> Int {
        column.longest <= fitLimit
            ? column.longest : Swift.max(Swift.min(column.longest, Self.flexibleShare), column.longestWord)
    }

    /// The longest cell a column may have and stay on one line, for this table.
    var fitLimit: Int {
        Self.fitLimits.first { estimate(fitLimit: $0) <= Self.room } ?? Self.fitLimits[Self.fitLimits.count - 1]
    }

    /// The attributes each cell gets, by column: `data-f` keeps a short column on one line, a long column a minimum width.
    func attribute(forColumn index: Int) -> String {
        let column = columns[index]
        if column.longest <= fitLimit { return " data-f" }
        let floor = Swift.min(Self.flexibleCeiling, Swift.max(Self.flexibleFloor, column.longestWord))
        return " style=\"min-width:\(floor)ch\""
    }

    /// `markup` with each cell's attribute put in, appended to `out`.
    func apply(to markup: ArraySlice<UInt8>, into out: inout OutputBuffer) {
        let attributes = columns.indices.map { Array(attribute(forColumn: $0).utf8) }
        var position = markup.startIndex
        for cell in cells {
            let at = Swift.min(markup.startIndex + cell.offset, markup.endIndex)
            if at > position { out.append(contentsOf: markup[position ..< at]) }
            position = Swift.max(position, at)
            out.append(contentsOf: attributes[cell.column])
        }
        out.append(contentsOf: markup[position...])
    }

    /// `markup` with each cell's attribute put in.
    func apply(to markup: String) -> String {
        var out = OutputBuffer()
        apply(to: Array(markup.utf8)[...], into: &out)
        return String(decoding: out.array, as: UTF8.self)
    }
}
