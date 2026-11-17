public import CoreGraphics

/// How a source editor looks (ADR-0008): one monospaced size (a heading bold and tinted, or, with `scalesHeadings`, also at the
/// page's size for its level), and the space around the text.
@available(macOS 26.0, *)
public struct MarkdownEditorConfiguration: Sendable, Equatable {
    public var fontSize: Double
    public var inset: CGSize
    /// A heading's text at the page's scale for its level, closer to what the page shows; off, every line has one height.
    public var scalesHeadings: Bool

    public init(fontSize: Double = 13, inset: CGSize = CGSize(width: 14, height: 16), scalesHeadings: Bool = false) {
        self.fontSize = fontSize
        self.inset = inset
        self.scalesHeadings = scalesHeadings
    }
}
