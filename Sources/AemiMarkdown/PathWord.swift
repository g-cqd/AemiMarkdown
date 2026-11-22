/// A word of a leaf block's text and whether it names a path (``MarkdownExtensions/pathWords``): the inline parser keeps the last one
/// it read, so a word holding many delimiters is read once.
struct PathWord {
    var bytes: Range<Int> = 0 ..< 0
    var isPath = false
}

extension InlineParser {
    /// What ends a word.
    private static let blanks = Array(" \t\n\r".utf8)
    /// What may open a word before its path: a quote, a bracket, or `=` as in `--file=/a/b`.
    private static let openers = Array("\"'([<=".utf8)

    /// Whether the delimiter run starting at `start` is inside a word that starts with `/` or `~/`, after any of `"'([<=` (ADR-0012).
    mutating func isInPathWord(_ start: Int) -> Bool {
        if lastWord.bytes.contains(start) { return lastWord.isPath }
        var low = start
        while low > 0, !Self.blanks.contains(text[low - 1]) { low -= 1 }
        var high = start
        while high < text.count, !Self.blanks.contains(text[high]) { high += 1 }
        var first = low
        while first < high, Self.openers.contains(text[first]) { first += 1 }
        let head = text[first ..< Swift.min(first + 2, high)]
        let isPath = head.first == UInt8(ascii: "/") || head.elementsEqual("~/".utf8)
        lastWord = PathWord(bytes: low ..< high, isPath: isPath)
        return isPath
    }
}
