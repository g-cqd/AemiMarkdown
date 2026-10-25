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
    /// The most bytes in one leaf block (a paragraph, a heading, a table cell) that the inline phase will parse. A longer one is plain text: its inline tree
    /// would take memory in proportion to its size, a few dozen bytes for each byte of it.
    public var maxLeafBytes: Int
    /// The most bytes in a link's destination or title. A longer one is not a link: a title can run over many lines, and a slot can name only 4 MiB.
    public var maxLinkBytes: Int

    /// The settings, brought inside what the tape format and the memory budget can hold: each is clamped to its floor and ceiling, so no setting traps.
    public init(
        maxContainerDepth: Int = 32, maxInlineDepth: Int = 32, maxLineBytes: Int = 1 << 20,
        maxDocumentBytes: Int = 64 << 20,
        maxTableColumns: Int = 64, maxInlineWorkPerByte: Int = 64, maxLeafBytes: Int = 1 << 20,
        maxLinkBytes: Int = 64 << 10
    ) {
        // @dl:disable near-clone -- one clamp per setting, in one shape
        self.maxContainerDepth = Self.clamp(maxContainerDepth, 1, 256)
        self.maxInlineDepth = Self.clamp(maxInlineDepth, 1, 256)
        self.maxLineBytes = Self.clamp(maxLineBytes, 1, Slot.maxRange)
        self.maxDocumentBytes = Self.clamp(maxDocumentBytes, 0, 1 << 30)
        // Two bits of alignment per column, in 128 bits.
        self.maxTableColumns = Self.clamp(maxTableColumns, 1, 64)
        self.maxInlineWorkPerByte = Self.clamp(maxInlineWorkPerByte, 1, 1024)
        self.maxLeafBytes = Self.clamp(maxLeafBytes, 1, Slot.maxRange)
        self.maxLinkBytes = Self.clamp(maxLinkBytes, 1, Slot.maxRange)
        // @dl:enable near-clone
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(value, low), high) }

    public static let `default` = MarkdownLimits()
}

// @dl:disable near-clone -- two option sets: the same declarations, one per flag, by the shape of an OptionSet
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
    public static let leafSizeLimit = MarkdownDiagnostics(rawValue: 1 << 8)
    public static let linkLengthLimit = MarkdownDiagnostics(rawValue: 1 << 9)
}

/// The syntax beyond CommonMark that the parser reads. Every one is on by default (``github``); with none, the parser is CommonMark 0.31.2 and nothing else.
public struct MarkdownExtensions: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// GitHub tables: `| a | b |` with a delimiter row `| --- | --- |`.
    public static let tables = MarkdownExtensions(rawValue: 1 << 0)
    /// `~~text~~` and `~text~`.
    public static let strikethrough = MarkdownExtensions(rawValue: 1 << 1)
    /// Bare `www.example.com`, `https://example.com` and `me@example.com` become links.
    public static let autolinks = MarkdownExtensions(rawValue: 1 << 2)

    /// `- [ ] item` and `- [x] item`: a checkbox before the text of the item.
    public static let taskLists = MarkdownExtensions(rawValue: 1 << 3)

    /// `[^label]` in the text, and `[^label]: …` blocks that hold what it refers to.
    public static let footnotes = MarkdownExtensions(rawValue: 1 << 4)

    /// `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!WARNING]` and `> [!CAUTION]` on the first line of a block quote, which GitHub draws as a callout. The block quote's
    /// payload says which, and the marker line is not part of its text.
    public static let alerts = MarkdownExtensions(rawValue: 1 << 5)
    /// `$x^2$` and `$$ … $$`, as GitHub reads them: the opening `$` is followed by something other than a space, the closing one is preceded by something other than a space and
    /// not followed by a digit. A shell line such as `"$A" "$B"` outside a code span can look like one, as it does on GitHub.
    public static let math = MarkdownExtensions(rawValue: 1 << 6)

    /// What cmark-gfm implements and the GitHub Flavored Markdown specification describes.
    public static let gfm: MarkdownExtensions = [.tables, .strikethrough, .autolinks, .taskLists, .footnotes]
    /// Everything GitHub renders that has a meaning in a terminal: GFM, alerts and math.
    public static let github: MarkdownExtensions = [.gfm, .alerts, .math]
}
// @dl:enable near-clone
