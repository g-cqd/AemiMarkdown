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
        var destination: Range<Int>?
        var title: Range<Int>?
        var matched = false
        let afterBracket = position
        if position < text.count, text[position] == UInt8(ascii: "(") {
            position += 1
            LinkSyntax.skipSpaceAndOneNewline(text, &position)
            if let found = LinkSyntax.destination(text, &position) {
                destination = found
                let afterDestination = position
                LinkSyntax.skipSpaceAndOneNewline(text, &position)
                if position > afterDestination { title = LinkSyntax.title(text, &position) }
                LinkSyntax.skipSpaceAndOneNewline(text, &position)
                if position < text.count, text[position] == UInt8(ascii: ")") {
                    position += 1
                    matched = true
                }
            }
            if !matched {
                position = afterBracket
                destination = nil
                title = nil
            }
        }
        var reference: ReferenceTable.Reference?
        if !matched {
            let labelStart = position
            let length = LinkSyntax.labelLength(text, &position)
            var label: Range<Int>?
            if length > 2 {
                label = (labelStart + 1) ..< (labelStart + length - 1)
            } else if !opener.bracketAfter {
                label = opener.index ..< close
            }
            if length == 0 { position = afterBracket }
            if let label, spend(label.count), let found = references.find(label: text[label]) {
                reference = found
                matched = true
            }
        }
        guard matched else {
            brackets.removeLast()
            position = afterBracket
            appendText(close, close + 1)
            return
        }
        guard wrapLink(opener: opener, destination: destination, title: title, reference: reference) else {
            brackets.removeLast()
            position = afterBracket
            appendText(close, close + 1)
            return
        }
        brackets.removeLast()
    }

    /// Builds the link or image node over what follows the opener on the tree. False if it would nest past the limit.
    private mutating func wrapLink(
        opener: Bracket, destination: Range<Int>?, title: Range<Int>?, reference: ReferenceTable.Reference?
    ) -> Bool {
        var height: Int32 = 0
        var node = tree.nodes[Int(opener.node)].next
        while node >= 0 {
            height = Swift.max(height, tree.nodes[Int(node)].height)
            node = tree.nodes[Int(node)].next
        }
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
        node = tree.nodes[Int(opener.node)].next
        while node != link {
            let next = tree.nodes[Int(node)].next
            tree.unlink(node)
            tree.link(node, lastChildOf: link)
            node = next
        }
        processEmphasis(bottom: opener.previousDelimiter)
        tree.unlink(opener.node)
        if !opener.isImage {
            // A link cannot contain a link: the `[` openers before this one stop being openers.
            for index in brackets.indices where !brackets[index].isImage { brackets[index].active = false }
        }
        return true
    }
}
