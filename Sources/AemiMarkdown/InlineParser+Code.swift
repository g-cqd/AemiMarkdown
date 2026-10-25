extension InlineParser {
    private static let longestBacktickRun = 64

    /// A run of backticks: a code span if a run of the same length follows, otherwise the backticks themselves (CommonMark 6.1).
    mutating func backticks() {
        let start = position
        var end = start
        while end < text.count, text[end] == UInt8(ascii: "`") { end += 1 }
        let length = end - start
        position = end
        // A run of this length with no closer after it means no later run of this length has one either: no scan needed.
        guard length <= Self.longestBacktickRun, !isExhausted(length) else {
            appendText(start, end)
            return
        }
        var scan = end
        while scan < text.count, spend() {
            guard text[scan] == UInt8(ascii: "`") else {
                scan += 1
                continue
            }
            var runEnd = scan
            while runEnd < text.count, text[runEnd] == UInt8(ascii: "`") { runEnd += 1 }
            if runEnd - scan == length {
                codeSpan(from: end, to: scan)
                position = runEnd
                return
            }
            scan = runEnd
        }
        markExhausted(length)
        appendText(start, end)
    }

    private func isExhausted(_ length: Int) -> Bool {
        length < 64
            ? backticksExhaustedLow & (1 << UInt64(length)) != 0
            : backticksExhaustedHigh & (1 << UInt64(length - 64)) != 0
    }

    private mutating func markExhausted(_ length: Int) {
        if length < 64 {
            backticksExhaustedLow |= 1 << UInt64(length)
        } else {
            backticksExhaustedHigh |= 1 << UInt64(length - 64)
        }
    }

    /// The code span whose content is `text[from ..< to]`. A line ending in it is a space; one space is stripped from each end if both have one and the
    /// content is not all spaces.
    private mutating func codeSpan(from: Int, to: Int) {
        if !text[from ..< to].contains(0x0A) {
            // One line, the common case: a range to trim, and no list of pieces.
            var lower = from
            var upper = to
            if upper - lower >= 2, text[lower] == 0x20, text[upper - 1] == 0x20,
                text[lower ..< upper].contains(where: { $0 != 0x20 })
            {
                lower += 1
                upper -= 1
            }
            let container = tree.append(InlineNode(kind: .codeSpan, height: 1))
            appendText(lower, upper, to: container, joining: false)
            return
        }
        codePieces.removeAll(keepingCapacity: true)
        var lineStart = from
        for index in from ..< to where text[index] == 0x0A {
            codePieces.append(lineStart ..< index)
            lineStart = index + 1
        }
        codePieces.append(lineStart ..< to)
        let multiline = codePieces.count > 1
        let firstIsSpace = codePieces[0].isEmpty ? multiline : text[codePieces[0].lowerBound] == 0x20
        let lastIsSpace =
            codePieces[codePieces.count - 1].isEmpty
            ? multiline : text[codePieces[codePieces.count - 1].upperBound - 1] == 0x20
        let allSpaces = codePieces.allSatisfy { $0.allSatisfy { text[$0] == 0x20 } }
        if firstIsSpace, lastIsSpace, !allSpaces {
            if codePieces[0].isEmpty {
                codePieces.removeFirst()
            } else {
                codePieces[0] = (codePieces[0].lowerBound + 1) ..< codePieces[0].upperBound
            }
            if let last = codePieces.last {
                if last.isEmpty {
                    codePieces.removeLast()
                } else {
                    codePieces[codePieces.count - 1] = last.lowerBound ..< (last.upperBound - 1)
                }
            }
        }
        let container = tree.append(InlineNode(kind: .codeSpan, height: 1))
        for (index, piece) in codePieces.enumerated() {
            if index > 0 { tree.append(InlineNode(kind: .softBreak), to: container) }
            appendText(piece.lowerBound, piece.upperBound, to: container, joining: false)
        }
    }
}
