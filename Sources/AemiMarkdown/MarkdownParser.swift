internal import AemiFrontMatter

/// Parses Markdown from UTF-8 bytes into a ``MarkdownDocument``, all at once or as it streams in (ADR-0001).
public struct MarkdownParser: Sendable {
    public let limits: MarkdownLimits
    public let extensions: MarkdownExtensions
    var source: ContiguousArray<UInt8> = []
    var blocks = SlotTape()
    var inlines = SlotTape()
    /// The top-level block index: three slots for each closed top-level block (source range, content hash, slot on the block tape), committed with the block tape (ADR-0003).
    var topIndex = SlotTape()
    /// For each leaf block whose inlines looked up a reference: its slot on the block tape and the stamp of what the lookups found, in slot order (ADR-0003).
    var stamps = SlotTape()
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
    /// An editor has put an edit's bytes in `source` and has not yet parsed them: the tapes are those of the document before it (ADR-0003).
    var spliced = false
    /// Steps the inline phase has taken so far, over every leaf block: what the work limit counts, kept so tests can show that the cost grows with the input.
    var inlineSteps = 0
    /// When a single open paragraph runs without line breaks for many bytes, an incremental parser keeps its inline tree across appends and snapshots.
    var openParagraphParser: InlineParser?
    var openParagraphParsedUpTo = 0
    /// The document's head (``MarkdownExtensions/frontMatter``), boxed: the parser is copied often and most documents have none.
    var head: HeadBox?
    /// Where the lines after the head start: lines before are the head's, not Markdown. `Int.max` while the head is undecided, so
    /// that every complete line waits for it, at the cost of one comparison per line.
    var headBodyStart = 0

    public init(extensions: MarkdownExtensions = .github, limits: MarkdownLimits = .default) {
        self.extensions = extensions
        self.limits = limits
        startHead()
    }

    /// Parses `bytes` as a whole document. Reference definitions anywhere apply to every link.
    /// - Complexity: O(n) in `bytes.count`, within the limits.
    public static func parse(
        _ bytes: [UInt8],
        extensions: MarkdownExtensions = .github,
        limits: MarkdownLimits = .default
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
        topIndex.removeAll()
        stamps.removeAll()
        if !references.isEmpty { references.removeAll() }
        lineStart = 0
        scanPosition = 0
        scannedUpTo = 0
        isFinished = false
        spliced = false
        inlineSteps = 0
        openParagraphParser = nil
        openParagraphParsedUpTo = 0
        startHead()
    }

    /// The document as the tapes stand. `finalBefore` is where the blocks that may still change begin; a finished document has none.
    func document(finalBefore: Int? = nil) -> MarkdownDocument {
        MarkdownDocument(
            source: source,
            blocks: blocks,
            inlines: inlines,
            index: topIndex,
            stamps: stamps,
            diagnostics: diagnostics,
            finalBefore: finalBefore ?? blocks.count,
            frontMatter: head?.state.found
        )
    }

    /// Where the top-level blocks that may still change begin on the block tape: the slot of the open top-level block, or the end of the tape
    /// when none is open, since a partial last line may still start one. Everything before it has closed, and a closed block is final.
    var openBlocksStart: Int {
        guard !isFinished else { return blocks.count }
        return state.open.count > 1 ? state.open[1].slot : blocks.count
    }
}
