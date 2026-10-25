extension InlineParser {
    /// A `]` that ends `[^label]` (or `![^label]`) where a footnote with that label is defined: the brackets and the label become one reference leaf. False if this is not one.
    mutating func footnoteReference(opener: Bracket, close: Int) -> Bool {
        guard opener.index < close, text[opener.index] == UInt8(ascii: "^") else { return false }
        let label = (opener.index + 1) ..< close
        guard !label.isEmpty, references.hasFootnote(label: text[label], scratch: &referenceKey),
            !text[label].contains(where: { ASCIIClass.isWhitespace($0) || $0 == UInt8(ascii: "[") })
        else { return false }
        // What was scanned since the `[` was the label, as text: it goes, and the delimiters it made with it.
        var next = tree.nodes[Int(opener.node)].next
        while next >= 0 {
            let following = tree.nodes[Int(next)].next
            tree.unlink(next)
            next = following
        }
        if opener.isImage {
            // `![^1]` is an exclamation mark and a reference: the `!` stays as text.
            tree.nodes[Int(opener.node)].length = 1
            tree.nodes[Int(opener.node)].payload = 0
        } else {
            tree.unlink(opener.node)
        }
        delimiterTop = opener.previousDelimiter
        if delimiterTop >= 0 { delimiters[Int(delimiterTop)].next = -1 }
        brackets.removeLast()
        tree.append(InlineNode(kind: .footnoteReference, start: sourceOffset(label.lowerBound), length: label.count))
        return true
    }
}
