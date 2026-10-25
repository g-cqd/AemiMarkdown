extension InlineParser {
    /// A run of `$`: math if the run is one or two and a closing `$` or `$$` follows by GitHub's rules, and otherwise the dollars as text.
    mutating func dollar() {
        let start = position
        var end = start
        while end < text.count, text[end] == UInt8(ascii: "$") { end += 1 }
        position = end
        let count = end - start
        guard extensions.contains(.math), count <= 2, let close = mathClose(opening: end, count: count) else {
            appendText(start, end)
            return
        }
        let container = tree.append(InlineNode(kind: .math, payload: count == 2 ? 1 : 0, height: 1))
        var lineStart = end
        for index in end ..< close where text[index] == 0x0A {
            appendText(lineStart, index, to: container, joining: false)
            tree.append(InlineNode(kind: .softBreak), to: container)
            lineStart = index + 1
        }
        appendText(lineStart, close, to: container, joining: false)
        position = close + count
    }

    /// The index of the `$` or `$$` that closes math whose text starts at `opening`, or nil.
    ///
    /// One dollar: the text starts with something other than white space; the closing one has something other than white space before it and no digit after it; a
    /// run of two or more dollars does not close it. Two dollars: the text is not all white space, and the closing run is exactly two.
    /// - Complexity: O(rest of the block) once; a failed search is remembered, so many unmatched dollars do not each scan to the end.
    private mutating func mathClose(opening: Int, count: Int) -> Int? {
        if count == 1 ? singleDollarExhausted : doubleDollarExhausted { return nil }
        let startsWell = opening < text.count && !ASCIIClass.isWhitespace(text[opening])
        let found: Int? =
            count == 1 ? (startsWell ? closingSingleDollar(from: opening) : nil) : closingDoubleDollar(from: opening)
        // What was scanned counts against the work budget: the distance to the closer, or to the end if there is none. Nothing is scanned for a `$` followed by a space.
        if count == 2 || startsWell { _ = spend((found ?? text.count) - opening) }
        if found == nil, count == 1, startsWell { singleDollarExhausted = true }
        if found == nil, count == 2 { doubleDollarExhausted = true }
        return found
    }

    private func closingSingleDollar(from start: Int) -> Int? {
        var index = start
        while index < text.count {
            let byte = text[index]
            if byte == UInt8(ascii: "\\") {
                index += 2
            } else if byte == UInt8(ascii: "$") {
                var run = index
                while run < text.count, text[run] == UInt8(ascii: "$") { run += 1 }
                if run - index == 1, index > start, !ASCIIClass.isWhitespace(text[index - 1]),
                    run >= text.count || !ASCIIClass.isDigit(text[run])
                {
                    return index
                }
                index = run
            } else {
                index += 1
            }
        }
        return nil
    }

    private func closingDoubleDollar(from start: Int) -> Int? {
        var index = start
        while index < text.count {
            if text[index] == UInt8(ascii: "\\") {
                index += 2
            } else if text[index] == UInt8(ascii: "$") {
                var run = index
                while run < text.count, text[run] == UInt8(ascii: "$") { run += 1 }
                if run - index == 2, text[start ..< index].contains(where: { !ASCIIClass.isWhitespace($0) }) {
                    return index
                }
                index = run
            } else {
                index += 1
            }
        }
        return nil
    }
}
