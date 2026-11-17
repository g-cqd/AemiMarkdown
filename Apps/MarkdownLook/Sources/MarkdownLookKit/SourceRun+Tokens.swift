internal import AemiLexers
internal import AemiMarkdown

@available(macOS 26.0, *)
extension SourceRun {
    /// The lines of one block, scanned as one text (a string or a comment may run over several), and cut back into lines.
    /// - Parameters:
    ///   - lines: The bytes of each line of the block in the source, in order.
    ///   - bytes: The source.
    ///   - language: The language the fence names.
    /// - Returns: Runs covering exactly `lines`: tokens, and plain code between them.
    static func tokens(of lines: [Range<Int>], in bytes: [UInt8], language: Language) -> [(
        bytes: Range<Int>, style: SourceRun
    )] {
        let plain = SourceRun.markdown(MarkdownSourceStyle(kind: .code))
        var joined: [UInt8] = []
        var starts: [Int] = []
        for line in lines {
            starts.append(joined.count)
            joined += bytes[line.clamped(to: 0 ..< bytes.count)]
            joined.append(0x0A)
        }
        guard joined.count <= CodeHighlighter.byteLimit else { return lines.map { ($0, plain) } }
        let found = CodeHighlighter.spans(joined, language: language)
        var out: [(bytes: Range<Int>, style: SourceRun)] = []
        var next = 0
        for (number, line) in lines.enumerated() {
            let low = starts[number]
            let high = low + line.count
            var cursor = low
            while next < found.count, found[next].range.lowerBound < high {
                let token = found[next]
                let from = Swift.max(token.range.lowerBound, low)
                let upto = Swift.min(token.range.upperBound, high)
                if from > cursor { out.append((source(cursor, from, line, low), plain)) }
                if upto > from { out.append((source(from, upto, line, low), .token(token.kind))) }
                cursor = Swift.max(cursor, upto)
                // A token that goes on past this line is taken up again on the next.
                if token.range.upperBound > high { break }
                next += 1
            }
            if high > cursor { out.append((source(cursor, high, line, low), plain)) }
        }
        return out
    }

    /// A range of the joined text, back in the source.
    private static func source(_ from: Int, _ upto: Int, _ line: Range<Int>, _ low: Int) -> Range<Int> {
        (line.lowerBound + from - low) ..< (line.lowerBound + upto - low)
    }
}
