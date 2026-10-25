extension MarkdownParser {
    /// The label range of a footnote definition that starts at `index`: `[^label]:`, the label with no space and no `]`.
    static func footnoteLabel(_ source: ContiguousArray<UInt8>, _ index: Int, _ end: Int) -> Range<Int>? {
        guard index + 3 < end, source[index] == UInt8(ascii: "["), source[index + 1] == UInt8(ascii: "^") else {
            return nil
        }
        var i = index + 2
        while i < end, source[i] != UInt8(ascii: "]"), !ASCIIClass.isWhitespace(source[i]),
            source[i] != UInt8(ascii: "[")
        { i += 1 }
        guard i > index + 2, i + 1 < end + 1, i < end, source[i] == UInt8(ascii: "]"), i + 1 < end,
            source[i + 1] == UInt8(ascii: ":")
        else {
            return nil
        }
        return (index + 2) ..< i
    }

    /// Opens a footnote definition for `label`, which continues like a list item with four columns of indentation, and positions the cursor at its first text.
    mutating func openFootnote(label: Range<Int>, container: Int, _ end: Int) -> Int {
        references.insertFootnote(label: source[label])
        let index = addChild(
            .footnote, to: container, slot: Slot.make(.container, .footnoteDefinition, payload: 0, low: 0))
        blocks.append(Slot.make(.range, .footnoteLabel, payload: label.count, low: label.lowerBound))
        state.open[index].markerOffset = 0
        state.open[index].padding = 4
        advance(label.upperBound + 2 - state.offset, columns: false, end)
        // The spaces after the colon are not content: `[^a]:       text` is a paragraph, not a code block.
        while BlockScanner.isSpaceOrTab(peek(state.offset, end)) { advance(1, columns: true, end) }
        return index
    }
}
