public import CoreGraphics

/// How a source editor looks (ADR-0008): one monospaced size everywhere (a heading is bold and tinted, not larger, so lines keep
/// one height), and the space around the text.
@available(macOS 26.0, *)
public struct MarkdownEditorConfiguration: Sendable, Equatable {
    public var fontSize: Double
    public var inset: CGSize

    public init(fontSize: Double = 13, inset: CGSize = CGSize(width: 14, height: 16)) {
        self.fontSize = fontSize
        self.inset = inset
    }
}
