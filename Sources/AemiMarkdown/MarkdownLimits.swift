/// The bounds that keep attacker-controlled input from using all of the CPU or memory (ADR-0001, decision 5).
///
/// A construct that would pass a bound is kept as plain text, and ``MarkdownDiagnostics`` says which bound it was. Nothing is
/// dropped and nothing traps.
public struct MarkdownLimits: Sendable, Equatable {
    /// The deepest nesting of block containers (quotes, lists). Past it, a line's container markers are text.
    public var maxContainerDepth: Int
    /// The deepest nesting of inline containers (emphasis, links). Past it, delimiters are text.
    public var maxInlineDepth: Int
    /// The longest line, in bytes. A longer one is cut into lines of this length for block structure.
    public var maxLineBytes: Int
    /// The most source bytes. Past it, `append` ignores further input and says so.
    public var maxDocumentBytes: Int
    /// The most columns in a table. A wider header row is a paragraph.
    public var maxTableColumns: Int
    /// The most delimiter-stack steps the inline phase takes in one leaf block, as a multiple of its length. It bounds the quadratic cases.
    public var maxInlineWorkPerByte: Int

    public init(
        maxContainerDepth: Int = 32, maxInlineDepth: Int = 32, maxLineBytes: Int = 1 << 20,
        maxDocumentBytes: Int = 64 << 20, maxTableColumns: Int = 64, maxInlineWorkPerByte: Int = 64
    ) {
        self.maxContainerDepth = maxContainerDepth
        self.maxInlineDepth = maxInlineDepth
        self.maxLineBytes = maxLineBytes
        self.maxDocumentBytes = maxDocumentBytes
        self.maxTableColumns = maxTableColumns
        self.maxInlineWorkPerByte = maxInlineWorkPerByte
    }

    public static let `default` = MarkdownLimits()
}

/// What the parser noticed about the input, for a renderer that must treat it as untrusted.
public struct MarkdownDiagnostics: OptionSet, Sendable, Equatable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    /// A control byte other than tab, line feed and carriage return appeared (ESC and NUL among them).
    public static let controlBytes = MarkdownDiagnostics(rawValue: 1 << 0)
    /// The input was not well-formed UTF-8.
    public static let invalidUTF8 = MarkdownDiagnostics(rawValue: 1 << 1)
    public static let containerDepthLimit = MarkdownDiagnostics(rawValue: 1 << 2)
    public static let inlineDepthLimit = MarkdownDiagnostics(rawValue: 1 << 3)
    public static let lineLengthLimit = MarkdownDiagnostics(rawValue: 1 << 4)
    public static let documentSizeLimit = MarkdownDiagnostics(rawValue: 1 << 5)
    public static let tableColumnLimit = MarkdownDiagnostics(rawValue: 1 << 6)
    public static let inlineWorkLimit = MarkdownDiagnostics(rawValue: 1 << 7)
}
