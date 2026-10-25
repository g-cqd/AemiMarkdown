extension MarkdownParser {
    static let tabStop = 4

    /// The byte at `index` in the current line, or 0 past its end.
    @inline(__always)
    func peek(_ index: Int, _ end: Int) -> UInt8 { index < end ? source[index] : 0 }

    /// Finds the first byte that is not a space or a tab, from the cursor, and the indent and blankness that follow from it.
    mutating func findFirstNonspace(_ end: Int) {
        var i = state.offset
        var column = state.column
        var toTab = Self.tabStop - column % Self.tabStop
        while i < end {
            let byte = source[i]
            if byte == 0x20 {
                i += 1
                column += 1
                toTab -= 1
                if toTab == 0 { toTab = Self.tabStop }
            } else if byte == 0x09 {
                i += 1
                column += toTab
                toTab = Self.tabStop
            } else {
                break
            }
        }
        state.firstNonspace = i
        state.firstNonspaceColumn = column
        state.indent = column - state.column
        state.blank = i >= end
    }

    /// Moves the cursor `count` bytes, or `count` columns if `columns` (a tab counts as the columns left to the next stop, and may be taken in part).
    mutating func advance(_ count: Int, columns: Bool, _ end: Int) {
        var remaining = count
        while remaining > 0, state.offset < end {
            if source[state.offset] == 0x09 {
                let toTab = Self.tabStop - state.column % Self.tabStop
                if columns {
                    state.partiallyConsumedTab = toTab > remaining
                    let step = Swift.min(remaining, toTab)
                    state.column += step
                    if !state.partiallyConsumedTab { state.offset += 1 }
                    remaining -= step
                } else {
                    state.partiallyConsumedTab = false
                    state.column += toTab
                    state.offset += 1
                    remaining -= 1
                }
            } else {
                state.partiallyConsumedTab = false
                state.offset += 1
                state.column += 1
                remaining -= 1
            }
        }
    }
}
