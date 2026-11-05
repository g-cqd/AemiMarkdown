/// How a stretch of Markdown *source* is to be coloured while it is typed: colour only, so every byte stays as written and editing, the cursor and copy are untouched (the highlighting of ask's draft, roadmap 0085 and 0151, made neutral).
///
/// A style says what the bytes are, not how they look: a view turns it into a terminal style, an `NSAttributedString` or a CSS class. The text of a mark takes the traits of what surrounds it (`**`, `_`, a link, a heading), and every byte no text
/// covers (a marker such as `**`, `#`, a backtick, a fence, `>`, `- `, a link's brackets) is a `.marker`, for the view to dim.
public struct MarkdownSourceStyle: Sendable, Hashable {
    public enum Kind: UInt8, Sendable {
        /// Prose, possibly with traits.
        case text
        /// A code span, or a line of a code block.
        case code
        /// The info string of a fence (the language).
        case codeLabel
        /// A link's destination or title.
        case linkTarget
        /// Inline HTML.
        case html
        /// A byte of syntax that no text covers.
        case marker
    }

    public struct Traits: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let strong = Traits(rawValue: 1 << 0)
        public static let emphasis = Traits(rawValue: 1 << 1)
        public static let strikethrough = Traits(rawValue: 1 << 2)
        /// The text of a link, an image's description, or an autolink.
        public static let link = Traits(rawValue: 1 << 3)
    }

    public var kind: Kind
    public var traits: Traits
    /// 1 to 6 for the text of an ATX heading (`# Title`), else 0. A setext heading is left plain: its meaning comes from the line typed after it.
    public var headingLevel: Int

    public init(kind: Kind, traits: Traits = [], headingLevel: Int = 0) {
        self.kind = kind
        self.traits = traits
        self.headingLevel = headingLevel
    }
}

/// A run of source bytes and its style. The runs of a result are in order and do not overlap; plain text and white space between marks are in none.
public struct MarkdownSourceSpan: Sendable, Hashable {
    public var bytes: Range<Int>
    public var style: MarkdownSourceStyle

    public init(bytes: Range<Int>, style: MarkdownSourceStyle) {
        self.bytes = bytes
        self.style = style
    }
}

public enum MarkdownSourceHighlighter {
    /// A draft this short is parsed whole: a window would save nothing measurable.
    static let wholeParseBytes = 8_192

    /// The most bytes that are coloured. A longer text is coloured as far as its last line ending before the limit and no further: a parse costs time in proportion to the text, and a keystroke must not wait on a megabytes-long paste.
    public static let defaultMaxBytes = 1 << 20

    /// The styled runs of `bytes`, in order; empty for plain prose.
    ///
    /// With `visible`, a range of bytes the view shows, a text over 8 KiB is parsed only around it (from the last line where parsing can restart and give the same result, to the end of the last line shown), so a keystroke costs the window's parse and
    /// not the document's; the runs returned cover that window and may extend beyond it, and what they colour inside `visible` is what parsing the whole text colours there (tested across fences, lists, quotes and indented code, with accents and CRLF).
    /// Offsets are of `bytes` in every case. Any bytes are accepted: ill-formed UTF-8, NUL, a text with no line ending.
    /// - Complexity: O(n) in the bytes parsed, which are the window's, or the first `maxBytes`.
    public static func spans(
        of bytes: [UInt8],
        extensions: MarkdownExtensions = [.gfm, .alerts],
        visible: Range<Int>? = nil,
        maxBytes: Int = defaultMaxBytes
    ) -> [MarkdownSourceSpan] {
        let limit = clampedLimit(bytes, maxBytes: maxBytes)
        guard limit > 0, bytes[..<limit].contains(where: { markerBytes[Int($0)] }) else { return [] }
        guard let visible, limit > wholeParseBytes else {
            return spans(of: bytes[..<limit], offset: 0, extensions: extensions)
        }
        let lower = Swift.min(Swift.max(visible.lowerBound, 0), limit)
        let upper = Swift.min(Swift.max(visible.upperBound, lower), limit)
        let start = restart(in: bytes, before: lower, limit: limit)
        var end = upper
        while end < limit, bytes[end] != 0x0A { end += 1 }
        return spans(of: bytes[start ..< end], offset: start, extensions: extensions)
    }

    // MARK: One parse

    private static func spans(of slice: ArraySlice<UInt8>, offset: Int, extensions: MarkdownExtensions)
        -> [MarkdownSourceSpan]
    {
        let bytes = Array(slice)
        let document = MarkdownParser.parse(bytes, extensions: extensions)
        // One code for each source byte: 0 not covered by any leaf (a marker, or white space), 1 plain text, else 2 and the packed style.
        var codes = [UInt16](repeating: 0, count: bytes.count)
        var walk = Walk(bytes: bytes)
        for event in document.events {
            guard let (range, style) = walk.step(event) else { continue }
            let code = style.map { 2 + pack($0) } ?? 1
            for index in range where index >= 0 && index < codes.count { codes[index] = code }
        }
        let marker = 2 + pack(MarkdownSourceStyle(kind: .marker))
        for index in codes.indices where codes[index] == 0 && !isSpace(bytes[index]) { codes[index] = marker }
        var spans: [MarkdownSourceSpan] = []
        var start = 0
        var current: UInt16 = 0
        func close(at end: Int) {
            if current >= 2, end > start {
                spans.append(MarkdownSourceSpan(bytes: offset + start ..< offset + end, style: unpack(current - 2)))
            }
        }
        for index in codes.indices where codes[index] != current {
            close(at: index)
            current = codes[index]
            start = index
        }
        close(at: codes.count)
        return spans
    }

    /// The bytes some construct starts with; a text with none of them is prose, and is not parsed.
    private static let markerBytes: [Bool] = {
        var table = [Bool](repeating: false, count: 256)
        for byte in "*_`#[]>~|!<-+=0123456789:\\&$".utf8 { table[Int(byte)] = true }
        return table
    }()

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }

    /// A style in ten bits: the kind, the traits, the heading level.
    private static func pack(_ style: MarkdownSourceStyle) -> UInt16 {
        UInt16(style.kind.rawValue) | UInt16(style.traits.rawValue) << 3 | UInt16(
            Swift.min(Swift.max(style.headingLevel, 0), 7)
        ) << 7
    }

    private static func unpack(_ value: UInt16) -> MarkdownSourceStyle {
        MarkdownSourceStyle(
            kind: MarkdownSourceStyle.Kind(rawValue: UInt8(value & 0b111)) ?? .text,
            traits: MarkdownSourceStyle.Traits(rawValue: UInt8((value >> 3) & 0b1111)),
            headingLevel: Int((value >> 7) & 0b111)
        )
    }

    /// How many of `bytes` are coloured: all of them, or as far as the last line ending within `maxBytes`.
    private static func clampedLimit(_ bytes: [UInt8], maxBytes: Int) -> Int {
        guard bytes.count > maxBytes else { return bytes.count }
        var end = Swift.max(maxBytes, 0)
        while end > 0, bytes[end - 1] != 0x0A { end -= 1 }
        return end
    }

    // MARK: The walk

    /// The containers open at each point of a walk, and the style each leaf's bytes take.
    private struct Walk {
        let bytes: [UInt8]
        private var open: [MarkdownNode] = []
        /// Per open heading: whether it is an ATX heading, decided at its first leaf.
        private var atx: Bool?

        init(bytes: [UInt8]) { self.bytes = bytes }

        /// The bytes a leaf covers and their style (nil for plain text), or nil for an event that covers none.
        mutating func step(_ event: MarkdownEvent) -> (Range<Int>, MarkdownSourceStyle?)? {
            switch event {
                case .enter(let node):
                    open.append(node)
                    if node.kind == .heading { atx = nil }
                    return nil
                case .exit:
                    _ = open.popLast()
                    return nil
                case .leaf(let node):
                    guard !node.range.isEmpty else { return nil }
                    return (node.range, style(of: node))
            }
        }

        private mutating func style(of leaf: MarkdownNode) -> MarkdownSourceStyle? {
            switch leaf.kind {
                case .codeLine: return MarkdownSourceStyle(kind: .code)
                case .infoString: return MarkdownSourceStyle(kind: .codeLabel)
                case .linkDestination, .linkTitle: return MarkdownSourceStyle(kind: .linkTarget)
                case .htmlInline: return MarkdownSourceStyle(kind: .html)
                default: break
            }
            var traits: MarkdownSourceStyle.Traits = []
            var heading = 0
            for node in open {
                switch node.kind {
                    case .codeSpan: return MarkdownSourceStyle(kind: .code)
                    case .link, .image, .autolink: traits.insert(.link)
                    case .strong: traits.insert(.strong)
                    case .emphasis: traits.insert(.emphasis)
                    case .strikethrough: traits.insert(.strikethrough)
                    case .heading where isATX(leaf): heading = Swift.min(Swift.max(node.payload, 1), 6)
                    default: break
                }
            }
            return traits.isEmpty && heading == 0
                ? nil : MarkdownSourceStyle(kind: .text, traits: traits, headingLevel: heading)
        }

        /// Whether the open heading starts with `#` on its line: decided once, at its first leaf.
        private mutating func isATX(_ leaf: MarkdownNode) -> Bool {
            if let atx { return atx }
            var index = leaf.range.lowerBound - 1
            while index >= 0, index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x23 { index -= 1 }
            let found = index >= 0 && index < bytes.count && bytes[index] == 0x23
            atx = found
            return found
        }
    }

    // MARK: The window

    /// The byte offset of the last line at or before `limit` where parsing can restart and give the same result: after a blank line, outside any fence, before a line that is not indented (so a list's continuation or indented code is not read out of
    /// context); 0 when there is none. A line counts once its end, its line feed or the text's end, is at or before `limit`.
    /// - Complexity: O(limit), one pass over the bytes before the window.
    private static func restart(in bytes: [UInt8], before limit: Int, limit total: Int) -> Int {
        var safe = 0
        var fence: (byte: UInt8, length: Int)?
        var previousBlank = true
        var lineStart = 0
        while lineStart <= total {
            var end = lineStart
            while end < total, bytes[end] != 0x0A { end += 1 }
            guard end <= limit else { break }
            let line = bytes[lineStart ..< end]
            let blank = line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
            let indented = line.first.map { $0 == 0x20 || $0 == 0x09 } ?? false
            // `previousBlank` is false inside a fence, so a line inside one is never a restart.
            if previousBlank, !blank, !indented { safe = lineStart }
            fence = step(fence, line)
            previousBlank = blank && fence == nil
            guard end < total else { break }
            lineStart = end + 1
        }
        return safe
    }

    /// The fence open after `line`: one opens on a line of three or more backticks or tildes (up to three spaces in), and closes on a line of at least as many of the same, with nothing after them but spaces.
    private static func step(_ open: (byte: UInt8, length: Int)?, _ line: ArraySlice<UInt8>) -> (
        byte: UInt8, length: Int
    )? {
        var index = line.startIndex
        while index < line.endIndex, index - line.startIndex < 3, line[index] == 0x20 { index += 1 }
        guard index < line.endIndex, line[index] == 0x60 || line[index] == 0x7E else { return open }
        let byte = line[index]
        var length = 0
        while index < line.endIndex, line[index] == byte {
            length += 1
            index += 1
        }
        guard length >= 3 else { return open }
        if let open {
            let rest = line[index...].allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
            return byte == open.byte && length >= open.length && rest ? nil : open
        }
        // A backtick fence's info string may not hold a backtick.
        if line[index...].contains(0x60) { return nil }
        return (byte, length)
    }
}
