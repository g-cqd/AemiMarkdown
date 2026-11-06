internal import AemiFrontMatter

/// What the parser knows of the document's head: the stream that locates it, the head found, and where its content began once its
/// opening fence was seen (an edit within reach of it may open or close a head).
struct HeadState: Sendable {
    var stream: FrontMatterStream
    var found: FrontMatter?
    var contentStart: Int?
}

/// ``HeadState`` behind one pointer.
indirect enum HeadBox: Sendable {
    case box(HeadState)

    var state: HeadState {
        switch self {
            case .box(let state): state
        }
    }
}

/// The document's head (``MarkdownExtensions/frontMatter``): located by AemiHMMML's rules (its ADR-0015), kept as one top-level block
/// of the lines as written. While it is undecided the complete lines wait, so a snapshot draws them as Markdown, provisionally; once it
/// is decided, they are the head's or they are parsed as Markdown, in order (ADR-0006).
extension MarkdownParser {
    /// Whether the head is undecided, so complete lines wait for it.
    var headPending: Bool { headBodyStart == Int.max }

    /// A new document's head: undecided if heads are read.
    mutating func startHead() {
        guard extensions.contains(.frontMatter) else {
            head = nil
            headBodyStart = 0
            return
        }
        let options = FrontMatterOptions(maximumHeadBytes: limits.maxFrontMatterBytes)
        head = .box(HeadState(stream: FrontMatterStream(options: options)))
        headBodyStart = .max
    }

    /// Whether the complete line at `start` is Markdown now: not while the head is undecided (the line waits), nor when the head
    /// holds it.
    mutating func admitLine(at start: Int) -> Bool {
        if headPending { decideHead(before: start) }
        return !headPending && start >= headBodyStart
    }

    /// Asks the head's stream again; once it has decided, writes the head or parses the lines that waited before `line`.
    mutating func decideHead(before line: Int) {
        guard headPending, var state = head?.state else { return }
        let location = state.stream.update(source, complete: isFinished)
        switch location {
            case .undecided: break
            case .open(_, _, let contentStart): state.contentStart = contentStart
            case .none:
                headBodyStart = 0
            case .closed(let found):
                headBodyStart = 0
                state.contentStart = found.content.lowerBound
                // The body starts a line, as every block does; text after a JSON head's `}` on its line makes it no head here.
                if found.bodyStart == source.count || isLineStart(found.bodyStart) { state.found = found }
        }
        head = .box(state)
        guard !headPending else { return }
        if let found = state.found {
            writeHead(found)
        } else {
            replayLines(upTo: line)
        }
    }

    /// The lines that waited for the head, from the start of the document to `line`, parsed as Markdown.
    private mutating func replayLines(upTo line: Int) {
        var start = 0
        while start < line {
            var end = start
            while end < line, source[end] != 0x0A, source[end] != 0x0D { end += 1 }
            cutLines(start: start, end: end)
            commitClosedBlocks()
            start = lineEndOffset(after: end)
        }
    }

    /// The head as the first top-level block: a ``NodeKind/frontMatter`` whose children are its content's lines.
    private mutating func writeHead(_ found: FrontMatter) {
        headBodyStart = found.bodyStart
        state.lineStartOffset = found.range.lowerBound
        let payload =
            switch found.format {
                case .yaml: 1
                case .toml: 2
                case .json: 3
            }
        _ = addChild(.frontMatter, to: 0, slot: Slot.make(.container, .frontMatter, payload: payload, low: 0))
        var line = found.content.lowerBound
        var lines = 0
        while line < found.content.upperBound {
            var end = line
            while end < found.content.upperBound, source[end] != 0x0A, source[end] != 0x0D { end += 1 }
            blocks.append(Slot.make(.range, .codeLine, payload: end - line, low: line))
            lines += 1
            line = Swift.min(lineEndOffset(after: end), found.content.upperBound)
            if line == end { break }
        }
        // Its fences are lines too, but a JSON head's braces are on its content's.
        state.lineNumber += found.format == .json ? lines : lines + 2
        state.consumedEnd = found.bodyStart
        closeAbove(0)
        commitClosedBlocks()
    }

    private func isLineStart(_ offset: Int) -> Bool {
        offset == 0 || source[offset - 1] == 0x0A || source[offset - 1] == 0x0D
    }
}
