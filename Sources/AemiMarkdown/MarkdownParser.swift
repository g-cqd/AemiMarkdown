/// Parses Markdown from UTF-8 bytes into a ``MarkdownDocument``, all at once or as it streams in (ADR-0001).
public struct MarkdownParser: Sendable {
    public let limits: MarkdownLimits
    var source: ContiguousArray<UInt8> = []
    var blocks: ContiguousArray<UInt64> = []
    var inlines: ContiguousArray<UInt64> = []
    var diagnostics: MarkdownDiagnostics = []
    var state = BlockState()
    /// Where the unprocessed part of the source starts: the beginning of the line the next byte belongs to.
    var lineStart = 0
    var isFinished = false

    public init(limits: MarkdownLimits = .default) {
        self.limits = limits
    }

    /// Parses `bytes` as a whole document. Reference definitions anywhere apply to every link.
    /// - Complexity: O(n) in `bytes.count`, within the limits.
    public static func parse(_ bytes: [UInt8], limits: MarkdownLimits = .default) -> MarkdownDocument {
        var parser = MarkdownParser(limits: limits)
        parser.append(bytes)
        parser.finish()
        return parser.document()
    }

    func document() -> MarkdownDocument {
        MarkdownDocument(source: source, blocks: blocks, inlines: inlines, diagnostics: diagnostics)
    }
}
