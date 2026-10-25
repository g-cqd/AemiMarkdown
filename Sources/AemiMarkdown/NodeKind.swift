/// What a tape slot is. Block kinds live on the block tape, inline kinds on the inline tape.
///
/// The raw value is stored in six bits of a slot, so there are at most 64 kinds; `maxRaw` is checked by a test.
public enum NodeKind: UInt8, Sendable, CaseIterable {
    // MARK: Block containers and leaf blocks
    /// A leaf block with inlines. Payload: nothing.
    case paragraph = 0
    /// A leaf block with inlines. Payload: the level, 1 to 6.
    case heading
    /// A container. Payload: 0, or the alert it opens with: 1 note, 2 tip, 3 important, 4 warning, 5 caution.
    case blockQuote
    /// A container. Payload: `ListFlags`. An ordered list's first child is a ``listStart`` marker.
    case list
    /// A container whose children are blocks.
    case listItem
    /// A container: a footnote's content. Its first child is its ``footnoteLabel``.
    case footnoteDefinition
    /// The label of a footnote definition, as a range of the source (without `[^` and `]`).
    case footnoteLabel
    /// A container whose children are ``codeLine`` leaves, after an optional ``infoString``. Payload: 1 if fenced.
    case codeBlock
    /// A container whose children are ``codeLine`` leaves. The lines are raw HTML, shown as text.
    case htmlBlock
    /// A marker leaf.
    case thematicBreak
    /// A container. Payload: the column count.
    case table
    /// A container. Payload: 1 for the header row.
    case tableRow
    /// A leaf block with inlines. Payload: alignment (0 none, 1 left, 2 center, 3 right).
    case tableCell

    // MARK: Block leaves that name source bytes
    /// One line of a code or HTML block, without its line ending. The range may be empty.
    case codeLine
    /// The info string of a fenced code block, trimmed.
    case infoString
    /// A value leaf: an ordered list's start number.
    case listStart
    /// A value leaf: the number of spaces a partly consumed tab leaves at the start of the next ``codeLine`` or text.
    case virtualSpaces

    // MARK: Inline containers
    case emphasis
    case strong
    case strikethrough
    /// Children: ``linkDestination``, then ``linkTitle`` if the payload is 1, then the inline content.
    case link
    /// As ``link``. The content is the image's description.
    case image
    /// An autolink. Payload: 0 for `<scheme:…>`, 1 for `<a@b>`, 2 for a bare `www.` or URL. Child: one ``text``.
    case autolink
    /// Math, as `$…$` (payload 0) or `$$…$$` (payload 1). Children: ``text`` and ``softBreak`` leaves, as in a code span; the text is TeX, shown as it was written.
    case math
    /// A code span. Children: ``text`` and ``softBreak`` leaves; the renderer shows a break as a space.
    case codeSpan

    // MARK: Inline leaves
    /// A run of text, as a range of the source.
    case text
    /// A reference to a footnote, as the range of its label in the source. Only a label that a definition has becomes one.
    case footnoteReference
    /// Raw inline HTML, as a range of the source.
    case htmlInline
    /// A character reference such as `&amp;`, as a range of the source; ``MarkdownDocument/decode(_:)`` turns it into text.
    case entity
    case linkDestination
    case linkTitle
    /// A marker leaf that opens the inline run of a task list item's first paragraph. Payload: 1 if checked.
    case taskMarker
    /// A marker leaf: a line ending inside a paragraph.
    case softBreak
    /// A marker leaf.
    case hardBreak
    /// Ends an inline run on the inline tape.
    case runEnd

    /// The largest raw value any kind has.
    public static var maxRaw: UInt8 { allCases.map(\.rawValue).max() ?? 0 }
}
