/// A formatting command of the source editor (ADR-0008), as a function of the text and the selection: nothing is changed here,
/// the edit it gives is applied by whoever holds the text (`MarkdownSource.perform`), which makes it one step of undo. Each
/// command toggles: asked of text that has the format already, it takes the format away.
@available(macOS 26.0, *)
public enum MarkdownCommand: Sendable, Hashable {
    case bold, italic, strikethrough, code, link
    /// Levels 1 to 6; another level is cut to them.
    case heading(Int)
    case bulletList, numberedList, taskList, quote, codeBlock

    /// The edit that does the command for `selection` (UTF-16 units; cut to the text).
    /// - Complexity: O(the text), for its UTF-16 units; the work itself is on the selection, or on the lines it touches.
    public func edit(in text: String, selection: Range<Int>) -> MarkdownEdit {
        let units = Array(text.utf16)
        let low = min(max(selection.lowerBound, 0), units.count)
        let range = low ..< min(max(selection.upperBound, low), units.count)
        return switch self {
            case .bold: MarkdownInlineEdit.toggle("**", in: units, range)
            case .italic: MarkdownInlineEdit.toggle("_", in: units, range)
            case .strikethrough: MarkdownInlineEdit.toggle("~~", in: units, range)
            case .code: MarkdownInlineEdit.toggle("`", in: units, range)
            case .link: MarkdownInlineEdit.link(in: units, range)
            case .heading, .bulletList, .numberedList, .taskList, .quote, .codeBlock:
                MarkdownLineEdit.apply(self, in: units, range)
        }
    }
}
