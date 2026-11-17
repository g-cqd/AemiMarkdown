internal import AemiMarkdown

/// A run of colour in the source editor: a Markdown style, or a token of fenced code whose language a scanner knows, by the
/// kind letter of ``CodeHighlighter``.
@available(macOS 26.0, *)
enum SourceRun: Hashable {
    case markdown(MarkdownSourceStyle)
    case token(String)

    /// The runs of `spans`, with the lines of each fence that names a known language split into its tokens and what lies
    /// between them. Another fence's lines, an indented block and a code span stay one `.code` run each.
    /// - Parameters:
    ///   - spans: The highlighter's runs of `bytes`, in order.
    ///   - bytes: The source.
    /// - Returns: Runs in order, not overlapping.
    /// - Complexity: O(the spans) plus one scan of each coloured block.
    static func runs(_ spans: [MarkdownSourceSpan], in bytes: [UInt8]) -> [(bytes: Range<Int>, style: SourceRun)] {
        var out: [(bytes: Range<Int>, style: SourceRun)] = []
        out.reserveCapacity(spans.count)
        var index = 0
        while index < spans.count {
            let span = spans[index]
            out.append((span.bytes, .markdown(span.style)))
            index += 1
            // A fence's info string comes right before its lines, and its closing fence (a marker) right after them.
            guard span.style.kind == .codeLabel, let language = CodeHighlighter.language(for: word(bytes, span.bytes))
            else { continue }
            var lines: [Range<Int>] = []
            while index < spans.count, spans[index].style.kind == .code {
                lines.append(spans[index].bytes)
                index += 1
            }
            out += tokens(of: lines, in: bytes, language: language)
        }
        return out
    }

    /// The first word of an info string: its language.
    private static func word(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        let clamped = range.clamped(to: 0 ..< bytes.count)
        let word = bytes[clamped].prefix { $0 != 0x20 && $0 != 0x09 }
        return String(decoding: word, as: UTF8.self)
    }
}
