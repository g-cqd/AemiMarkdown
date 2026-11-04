/// One line of a code block as the document holds it.
public struct MarkdownFenceLine: Sendable, Equatable {
    /// The line's bytes, without its line ending and without the indentation of the block's containers (a fence's own indentation is not part of it).
    public var range: Range<Int>
    /// The spaces a tab left: a tab that a list or a code block consumed only in part leaves virtual spaces at the start of this line.
    public var spacesFromTab: Int

    public init(range: Range<Int>, spacesFromTab: Int = 0) {
        self.range = range
        self.spacesFromTab = spacesFromTab
    }
}

/// Reads a code block's language and lines from its events and its source range, without copying a byte of text (ask roadmap 0202).
///
/// Four readers of fenced blocks used to collect the language and the lines each in its own way (TerminalKit's renderer, ask's fence scanner, the viewer
/// and the Quick Look preview). One reader, kept and reused, allocates nothing once its line array has grown.
///
/// ```swift
/// var reader = MarkdownFenceReader()
/// for block in document.topLevelBlocks {
///     guard let fence = reader.read(block, in: document) else { continue }
///     if document.source[fence.language] == Array("mermaid".utf8) { for line in reader.lines { _ = document.source[line.range] } }
/// }
/// ```
public struct MarkdownFenceReader: Sendable {
    /// What opens a code block.
    public enum Style: UInt8, Sendable {
        /// Three or more backticks.
        case backtick
        /// Three or more tildes.
        case tilde
        /// Lines indented by four spaces.
        case indented
    }

    /// What ``read(_:in:)`` found out about the block, apart from its lines.
    public struct Header: Sendable, Equatable {
        public var style: Style
        /// The info string, trimmed, as written (an entity or a backslash in it is not decoded); empty when there is none, and for an indented block.
        public var info: Range<Int>
        /// The info string's first word, as written. Compare it with the bytes you look for; `MarkdownDocument.decode` decodes an entity.
        public var language: Range<Int>
        /// Whether a closing fence ends the block: false for an input that ended inside it, true for an indented block, and **nil for a block inside a
        /// container**, which has no source range of its own to look at.
        public var isClosed: Bool?
    }

    /// The lines of the block read last, in order, until the next `read`.
    public private(set) var lines: ContiguousArray<MarkdownFenceLine> = []

    public init() {}

    /// Reads a top-level block if it is a code block.
    /// - Returns: nil when `block` is not a code block.
    /// - Complexity: O(the block's lines).
    public mutating func read(_ block: MarkdownBlock, in document: MarkdownDocument) -> Header? {
        guard block.node.kind == .codeBlock else { return nil }
        var events = document.events(of: block)
        guard case .enter(let opening)? = events.next() else { return nil }
        guard var header = read(opening, from: &events, in: document) else { return nil }
        if opening.payload == 1 {
            let (style, length) = Self.opening(of: block.sourceRange, in: document.source)
            header.style = style
            header.isClosed = Self.closes(block.sourceRange, in: document.source, style: style, openingLength: length)
        }
        return header
    }

    /// Reads the code block whose `enter` event `events` has just returned, to its `exit`: how a code block inside a list item or a block quote is read
    /// while walking a document. Its ``Header/isClosed`` is nil.
    /// - Returns: nil when `opening` is not a code block (and nothing is consumed).
    /// - Complexity: O(the block's lines).
    public mutating func read(_ opening: MarkdownNode, from events: inout MarkdownEvents, in document: MarkdownDocument)
        -> Header?
    {
        guard opening.kind == .codeBlock else { return nil }
        lines.removeAll(keepingCapacity: true)
        var info = 0 ..< 0
        var pendingSpaces = 0
        walk: while let event = events.next() {
            switch event {
                case .exit(let node) where node.kind == .codeBlock: break walk
                case .leaf(let node):
                    switch node.kind {
                        case .infoString: info = node.range
                        case .virtualSpaces: pendingSpaces = node.value
                        case .codeLine:
                            lines.append(MarkdownFenceLine(range: node.range, spacesFromTab: pendingSpaces))
                            pendingSpaces = 0
                        default: break
                    }
                default: break
            }
        }
        guard opening.payload == 1 else {
            return Header(style: .indented, info: 0 ..< 0, language: 0 ..< 0, isClosed: true)
        }
        var word = info
        if let end = document.source[info].firstIndex(where: { $0 == 0x20 || $0 == 0x09 }) {
            word = info.lowerBound ..< end
        }
        return Header(
            style: Self.style(before: info, or: lines.first?.range, in: document.source),
            info: info,
            language: word,
            isClosed: nil
        )
    }

    /// The fence's character, found by looking back from the info string, or from the first code line, over the fence line's end.
    private static func style(before info: Range<Int>, or firstLine: Range<Int>?, in source: ContiguousArray<UInt8>)
        -> Style
    {
        var index = info.lowerBound
        if info.isEmpty {
            guard let firstLine else { return .backtick }
            index = firstLine.lowerBound
            // The start of that line, then the end of the fence line before it.
            while index > 0, source[index - 1] != 0x0A, source[index - 1] != 0x0D { index -= 1 }
            while index > 0, source[index - 1] == 0x0A || source[index - 1] == 0x0D { index -= 1 }
        }
        while index > 0, source[index - 1] == 0x20 || source[index - 1] == 0x09 { index -= 1 }
        return index > 0 && source[index - 1] == UInt8(ascii: "~") ? .tilde : .backtick
    }

    /// The fence character and length of the block's first line: up to three spaces, then a run of backticks or tildes.
    private static func opening(of range: Range<Int>, in source: ContiguousArray<UInt8>) -> (Style, Int) {
        var index = range.lowerBound
        while index < range.upperBound, index - range.lowerBound < 3, source[index] == 0x20 { index += 1 }
        guard index < range.upperBound else { return (.backtick, 0) }
        let character = source[index]
        var length = 0
        while index + length < range.upperBound, source[index + length] == character { length += 1 }
        return (character == UInt8(ascii: "~") ? .tilde : .backtick, length)
    }

    /// Whether the block's last line, which is not its first, is a closing fence: up to three spaces, at least as many fence characters as opened it,
    /// and nothing but spaces and tabs after them.
    private static func closes(_ range: Range<Int>, in source: ContiguousArray<UInt8>, style: Style, openingLength: Int)
        -> Bool
    {
        guard openingLength >= 3, !range.isEmpty else { return false }
        var lineStart = range.upperBound
        while lineStart > range.lowerBound, source[lineStart - 1] != 0x0A, source[lineStart - 1] != 0x0D {
            lineStart -= 1
        }
        guard lineStart > range.lowerBound else { return false }  // the only line is the opening one
        var index = lineStart
        while index < range.upperBound, index - lineStart < 3, source[index] == 0x20 { index += 1 }
        let character: UInt8 = style == .tilde ? UInt8(ascii: "~") : UInt8(ascii: "`")
        var run = 0
        while index + run < range.upperBound, source[index + run] == character { run += 1 }
        guard run >= openingLength else { return false }
        return source[(index + run) ..< range.upperBound].allSatisfy { $0 == 0x20 || $0 == 0x09 }
    }
}
