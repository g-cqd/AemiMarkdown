/// Parses Markdown from UTF-8 bytes into a ``MarkdownDocument``, all at once or as it streams in (ADR-0001).
public struct MarkdownParser: Sendable {
    public let limits: MarkdownLimits
    public let extensions: MarkdownExtensions
    var source: ContiguousArray<UInt8> = []
    var blocks: ContiguousArray<UInt64> = []
    var inlines: ContiguousArray<UInt64> = []
    var diagnostics: MarkdownDiagnostics = []
    var state = BlockState()
    var references = ReferenceTable()
    var inlineParser = InlineParser()
    /// Where the unprocessed part of the source starts: the beginning of the line the next byte belongs to.
    var lineStart = 0
    var isFinished = false

    public init(extensions: MarkdownExtensions = .all, limits: MarkdownLimits = .default) {
        self.extensions = extensions
        self.limits = limits
    }

    /// Parses `bytes` as a whole document. Reference definitions anywhere apply to every link.
    /// - Complexity: O(n) in `bytes.count`, within the limits.
    public static func parse(
        _ bytes: [UInt8], extensions: MarkdownExtensions = .all, limits: MarkdownLimits = .default
    ) -> MarkdownDocument {
        var parser = MarkdownParser(extensions: extensions, limits: limits)
        parser.append(bytes)
        parser.finish()
        return parser.document()
    }

    func document() -> MarkdownDocument {
        MarkdownDocument(source: source, blocks: blocks, inlines: inlines, diagnostics: diagnostics)
    }
}
