/// Recognisers for the first bytes of a block, over `source[index ..< end]` (one line, without its ending). Each looks only forward and allocates nothing.
enum BlockScanner {
    typealias Bytes = ContiguousArray<UInt8>

    @inline(__always) static func isSpaceOrTab(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }

    /// The number of `#` of an ATX heading's opening sequence (1 to 6) that starts at `index`, if a space, a tab or the end follows it.
    static func atxHeadingLevel(_ source: Bytes, _ index: Int, _ end: Int) -> Int? {
        var i = index
        while i < end, source[i] == UInt8(ascii: "#") { i += 1 }
        let level = i - index
        guard level >= 1, level <= 6, i == end || isSpaceOrTab(source[i]) else { return nil }
        return level
    }

    /// Whether `source[index ..< end]` is a thematic break: three or more `*`, `-` or `_`, all the same, with spaces and tabs allowed between.
    static func isThematicBreak(_ source: Bytes, _ index: Int, _ end: Int) -> Bool {
        guard index < end else { return false }
        let marker = source[index]
        guard marker == UInt8(ascii: "*") || marker == UInt8(ascii: "-") || marker == UInt8(ascii: "_") else {
            return false
        }
        var count = 0
        for i in index ..< end {
            if source[i] == marker {
                count += 1
            } else if !isSpaceOrTab(source[i]) {
                return false
            }
        }
        return count >= 3
    }

    /// The character and length of an opening code fence at `index`. An info string after a backtick fence may not contain a backtick.
    static func codeFenceOpening(_ source: Bytes, _ index: Int, _ end: Int) -> (character: UInt8, length: Int)? {
        guard index < end else { return nil }
        let character = source[index]
        guard character == UInt8(ascii: "`") || character == UInt8(ascii: "~") else { return nil }
        var i = index
        while i < end, source[i] == character { i += 1 }
        guard i - index >= 3 else { return nil }
        if character == UInt8(ascii: "`") {
            for j in i ..< end where source[j] == UInt8(ascii: "`") { return nil }
        }
        return (character, i - index)
    }

    /// The length of a closing code fence of `character` at `index`, if only spaces and tabs follow it.
    static func codeFenceClosing(_ source: Bytes, _ index: Int, _ end: Int, character: UInt8) -> Int? {
        var i = index
        while i < end, source[i] == character { i += 1 }
        let length = i - index
        guard length >= 3 else { return nil }
        while i < end {
            guard isSpaceOrTab(source[i]) else { return nil }
            i += 1
        }
        return length
    }

    /// The level of a setext underline (`=` is 1, `-` is 2): a run of one of them, then only spaces and tabs.
    static func setextLevel(_ source: Bytes, _ index: Int, _ end: Int) -> Int? {
        guard index < end else { return nil }
        let marker = source[index]
        guard marker == UInt8(ascii: "=") || marker == UInt8(ascii: "-") else { return nil }
        var i = index
        while i < end, source[i] == marker { i += 1 }
        while i < end {
            guard isSpaceOrTab(source[i]) else { return nil }
            i += 1
        }
        return marker == UInt8(ascii: "=") ? 1 : 2
    }

    /// A list marker that starts at `index`.
    struct ListMarker: Equatable {
        var isOrdered: Bool
        /// The bullet character, or the delimiter (`.` or `)`) of an ordered marker.
        var character: UInt8
        var start: Int
        /// The marker's own length in bytes: 1, or the digits and the delimiter.
        var length: Int
    }

    /// The list marker at `index`. Something other than a space, a tab or the end must not follow it directly. A marker that interrupts a paragraph must be followed by
    /// something, and an ordered one must start at 1.
    static func listMarker(_ source: Bytes, _ index: Int, _ end: Int, interruptsParagraph: Bool) -> ListMarker? {
        guard index < end else { return nil }
        var marker: ListMarker
        var i = index
        let first = source[index]
        if first == UInt8(ascii: "*") || first == UInt8(ascii: "-") || first == UInt8(ascii: "+") {
            marker = ListMarker(isOrdered: false, character: first, start: 0, length: 1)
            i += 1
        } else if first >= 0x30, first <= 0x39 {
            var value = 0
            while i < end, source[i] >= 0x30, source[i] <= 0x39, i - index < 9 {
                value = value * 10 + Int(source[i] - 0x30)
                i += 1
            }
            guard i < end, source[i] == UInt8(ascii: ".") || source[i] == UInt8(ascii: ")") else { return nil }
            marker = ListMarker(isOrdered: true, character: source[i], start: value, length: i + 1 - index)
            i += 1
            if interruptsParagraph && value != 1 { return nil }
        } else {
            return nil
        }
        guard i == end || isSpaceOrTab(source[i]) else { return nil }
        if interruptsParagraph {
            var j = i
            while j < end, isSpaceOrTab(source[j]) { j += 1 }
            if j == end { return nil }
        }
        return marker
    }
}
