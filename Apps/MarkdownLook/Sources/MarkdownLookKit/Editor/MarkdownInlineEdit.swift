/// The commands that put markers around the selection (strong, emphasis, strikethrough, code, a link).
@available(macOS 26.0, *)
enum MarkdownInlineEdit {
    /// Wraps the selection in `marker`; takes the markers away when they are just outside it or at its two ends. With nothing
    /// selected the two markers are written and the caret is left between them.
    static func toggle(_ marker: String, in units: [UInt16], _ range: Range<Int>) -> MarkdownEdit {
        let mark = Array(marker.utf16)
        let width = mark.count
        let low = range.lowerBound
        let high = range.upperBound
        let inner = Array(units[range])
        if low >= width, high + width <= units.count, Array(units[(low - width) ..< low]) == mark,
            Array(units[high ..< (high + width)]) == mark
        {
            return MarkdownEdit(
                range: (low - width) ..< (high + width),
                replacement: text(inner),
                selection: (low - width) ..< (high - width)
            )
        }
        if inner.count >= 2 * width, Array(inner.prefix(width)) == mark, Array(inner.suffix(width)) == mark {
            let kept = Array(inner[width ..< (inner.count - width)])
            return MarkdownEdit(range: range, replacement: text(kept), selection: low ..< (low + kept.count))
        }
        return MarkdownEdit(
            range: range,
            replacement: marker + text(inner) + marker,
            selection: (low + width) ..< (high + width)
        )
    }

    /// `[selection](url)` with the address selected to be typed over; with nothing selected, `[text](url)` with the text selected.
    static func link(in units: [UInt16], _ range: Range<Int>) -> MarkdownEdit {
        let low = range.lowerBound
        guard !range.isEmpty else {
            return MarkdownEdit(range: range, replacement: "[text](url)", selection: (low + 1) ..< (low + 5))
        }
        let address = low + 1 + range.count + 2
        return MarkdownEdit(
            range: range,
            replacement: "[" + text(Array(units[range])) + "](url)",
            selection: address ..< (address + 3)
        )
    }

    static func text(_ units: [UInt16]) -> String { String(decoding: units, as: UTF16.self) }
}
