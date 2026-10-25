extension MarkdownDocument {
    /// The text a source range stands for once backslash escapes and character references are resolved: what a link target, a link title, an info
    /// string or an entity leaf means. A reference that names no character stays as written.
    /// - Complexity: O(range length).
    public func decode(_ range: Range<Int>) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(range.count)
        var i = range.lowerBound
        let end = Swift.min(range.upperBound, source.count)
        while i < end {
            let byte = source[i]
            if byte == UInt8(ascii: "\\"), i + 1 < end, ASCIIClass.isPunctuation(source[i + 1]) {
                out.append(source[i + 1])
                i += 2
            } else if byte == UInt8(ascii: "&"),
                let (scalars, length) = CharacterReference.decode(source, at: i, end: end)
            {
                for scalar in scalars { out.append(contentsOf: Array(String(scalar).utf8)) }
                i += length
            } else {
                out.append(byte)
                i += 1
            }
        }
        return out
    }
}
