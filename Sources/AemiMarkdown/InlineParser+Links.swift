extension InlineParser {
    mutating func openBracket(isImage: Bool) {
        let start = position
        position += isImage ? 2 : 1
        let node = appendNode(.text, scratch: start, length: position - start, payload: 1)
        if !brackets.isEmpty { brackets[brackets.count - 1].bracketAfter = true }
        brackets.append(Bracket(node: node, previousDelimiter: delimiterTop, index: position, isImage: isImage))
    }

    /// A `]`: with an opener before it, tries an inline link `(…)`, then a reference `[label]`, `[]` or nothing, and wraps what lies after the opener.
    mutating func closeBracket() {
        let close = position
        position += 1
        guard let opener = brackets.last else {
            appendText(close, position)
            return
        }
        guard opener.active else {
            brackets.removeLast()
            appendText(close, position)
            return
        }
        let afterBracket = position
        var destination: Range<Int>?
        var title: Range<Int>?
        var reference: ReferenceTable.Reference?
        if let inline = inlineLink() {
            (destination, title) = inline
        } else {
            position = afterBracket
            reference = referenceLink(opener: opener, close: close)
        }
        guard destination != nil || reference != nil,
            wrapLink(opener: opener, destination: destination, title: title, reference: reference)
        else {
            brackets.removeLast()
            position = afterBracket
            appendText(close, close + 1)
            return
        }
        brackets.removeLast()
    }

    /// The `(destination "title")` at the position, which moves past it; nil if there is none. What the scans read is charged to the work budget, so many `](`
    /// with no end cost a bounded total.
    private mutating func inlineLink() -> (destination: Range<Int>, title: Range<Int>?)? {
        guard position < text.count, text[position] == UInt8(ascii: "(") else { return nil }
        var scan = LinkSyntax.Scan()
        defer {
            if scan.tooLong { diagnostics.insert(.linkLengthLimit) }
        }
        position += 1
        LinkSyntax.skipSpaceAndOneNewline(text, &position)
        guard let destination = LinkSyntax.destination(text, &position, limit: limits.maxLinkBytes, &scan) else {
            return nil
        }
        let afterDestination = position
        LinkSyntax.skipSpaceAndOneNewline(text, &position)
        let title =
            position > afterDestination ? LinkSyntax.title(text, &position, limit: limits.maxLinkBytes, &scan) : nil
        LinkSyntax.skipSpaceAndOneNewline(text, &position)
        guard position < text.count, text[position] == UInt8(ascii: ")"), spend(scan.bytes) else { return nil }
        position += 1
        return (destination, title)
    }

    /// The definition that `[label]`, `[]` or the text of the brackets themselves names; the position moves past a label that follows.
    private mutating func referenceLink(opener: Bracket, close: Int) -> ReferenceTable.Reference? {
        let afterBracket = position
        let length = LinkSyntax.labelLength(text, &position)
        var label: Range<Int>?
        if length > 2 {
            label = (afterBracket + 1) ..< (afterBracket + length - 1)
        } else if !opener.bracketAfter {
            label = opener.index ..< close
        }
        if length == 0 { position = afterBracket }
        guard let label, spend(label.count) else { return nil }
        return references.find(label: text[label])
    }

    /// Builds the link or image node over what follows the opener on the tree. False if it would nest past the limit.
    private mutating func wrapLink(
        opener: Bracket, destination: Range<Int>?, title: Range<Int>?, reference: ReferenceTable.Reference?
    ) -> Bool {
        let height = tree.height(after: opener.node, before: -1)
        guard Int(height) + 1 <= limits.maxInlineDepth else {
            diagnostics.insert(.inlineDepthLimit)
            return false
        }
        let hasTitle = title != nil || reference?.title != nil
        let link = tree.append(
            InlineNode(kind: opener.isImage ? .image : .link, payload: hasTitle ? 1 : 0, height: height + 1))
        // The destination and the title come first among the children, as source ranges.
        let destinationNode = InlineNode(kind: .linkDestination, start: 0, length: 0)
        var leaf = destinationNode
        if let destination {
            leaf.start = sourceOffset(destination.lowerBound)
            leaf.length = destination.count
        } else if let reference {
            leaf.start = reference.destination.lowerBound
            leaf.length = reference.destination.count
        }
        tree.append(leaf, to: link)
        if let title {
            let upper = sourceOffset(title.upperBound)
            let lower = sourceOffset(title.lowerBound)
            tree.append(InlineNode(kind: .linkTitle, start: lower, length: Swift.max(0, upper - lower)), to: link)
        } else if let referenceTitle = reference?.title {
            tree.append(
                InlineNode(kind: .linkTitle, start: referenceTitle.lowerBound, length: referenceTitle.count), to: link)
        }
        tree.moveSiblings(after: opener.node, before: link, into: link)
        processEmphasis(bottom: opener.previousDelimiter)
        tree.unlink(opener.node)
        if !opener.isImage {
            // A link cannot contain a link: the `[` openers before this one stop being openers.
            for index in brackets.indices where !brackets[index].isImage { brackets[index].active = false }
        }
        return true
    }
}
