/// Parses Markdown from UTF-8 bytes into a ``MarkdownDocument``, all at once or as it streams in (ADR-0001).
public struct MarkdownParser: Sendable {
    public let limits: MarkdownLimits
    public let extensions: MarkdownExtensions
    var source: ContiguousArray<UInt8> = []
    var blocks = SlotTape()
    var inlines = SlotTape()
    var diagnostics: MarkdownDiagnostics = []
    var state = BlockState()
    var references = ReferenceTable()
    var inlineParser = InlineParser()
    /// Where the unprocessed part of the source starts: the beginning of the line the next byte belongs to.
    var lineStart = 0
    /// Where scanning for a line ending resumes: the first byte not yet looked at, or a carriage return that waits for its line feed.
    var scanPosition = 0
    /// Where the check for control bytes and invalid UTF-8 resumes: everything before it was checked.
    var scannedUpTo = 0
    var isFinished = false
    /// Steps the inline phase has taken so far, over every leaf block: what the work limit counts, kept so tests can show that the cost grows with the input.
    var inlineSteps = 0

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

    /// Starts a new document. The parser keeps the memory it grew for the last one, so a parser used for one document after another allocates only when a
    /// document is larger than any before it. A snapshot of the last document still shares its storage; it is left alone, and the parser takes new.
    public mutating func reset() {
        if !source.isEmpty { source.removeAll(keepingCapacity: true) }
        blocks.removeAll()
        inlines.removeAll()
        diagnostics = []
        state.reset()
        if !references.isEmpty { references.removeAll() }
        lineStart = 0
        scanPosition = 0
        scannedUpTo = 0
        isFinished = false
        inlineSteps = 0
    }

    func document() -> MarkdownDocument {
        MarkdownDocument(source: source, blocks: blocks, inlines: inlines, diagnostics: diagnostics)
    }
}
