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
        guard length <= Self.longestBacktickRun, !backticksExhausted[length] else {
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
        backticksExhausted[length] = true
        appendText(start, end)
    }

    /// The code span whose content is `text[from ..< to]`. A line ending in it is a space; one space is stripped from each end if both have one and the
    /// content is not all spaces.
    private mutating func codeSpan(from: Int, to: Int) {
        var pieces: [Range<Int>] = []
        var lineStart = from
        for index in from ..< to where text[index] == 0x0A {
            pieces.append(lineStart ..< index)
            lineStart = index + 1
        }
        pieces.append(lineStart ..< to)
        let multiline = pieces.count > 1
        let firstIsSpace = pieces[0].isEmpty ? multiline : text[pieces[0].lowerBound] == 0x20
        let lastIsSpace =
            pieces[pieces.count - 1].isEmpty ? multiline : text[pieces[pieces.count - 1].upperBound - 1] == 0x20
        let allSpaces = pieces.allSatisfy { $0.allSatisfy { text[$0] == 0x20 } }
        if firstIsSpace, lastIsSpace, !allSpaces {
            if pieces[0].isEmpty {
                pieces.removeFirst()
            } else {
                pieces[0] = (pieces[0].lowerBound + 1) ..< pieces[0].upperBound
            }
            if let last = pieces.last {
                if last.isEmpty {
                    pieces.removeLast()
                } else {
                    pieces[pieces.count - 1] = last.lowerBound ..< (last.upperBound - 1)
                }
            }
        }
        let container = tree.append(InlineNode(kind: .codeSpan, height: 1))
        for (index, piece) in pieces.enumerated() {
            if index > 0 { tree.append(InlineNode(kind: .softBreak), to: container) }
            appendText(piece.lowerBound, piece.upperBound, to: container, joining: false)
        }
    }
}
