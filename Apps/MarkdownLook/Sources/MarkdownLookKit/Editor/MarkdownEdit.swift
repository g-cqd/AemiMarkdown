/// One replacement in a Markdown source, and where the selection goes after it (ADR-0008). Offsets are UTF-16 units, as a text
/// view counts: `range` in the text before the edit, `selection` in the text after it.
@available(macOS 26.0, *)
public struct MarkdownEdit: Sendable, Equatable {
    public var range: Range<Int>
    public var replacement: String
    public var selection: Range<Int>

    public init(range: Range<Int>, replacement: String, selection: Range<Int>) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}
