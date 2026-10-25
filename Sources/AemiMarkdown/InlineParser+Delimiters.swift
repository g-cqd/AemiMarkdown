extension InlineParser {
    private static func kindIndex(_ character: UInt8) -> Int {
        switch character {
            case UInt8(ascii: "*"): 0
            case UInt8(ascii: "_"): 1
            default: 2
        }
    }

    /// A run of `*`, `_` or `~`: text for now, and a delimiter that `processEmphasis` may turn into emphasis (CommonMark 6.2).
    mutating func delimiterRun(_ character: UInt8) {
        let start = position
        var end = start
        while end < text.count, text[end] == character { end += 1 }
        position = end
        let count = end - start
        // Strikethrough takes one or two tildes; a longer run is just text.
        if character == UInt8(ascii: "~"), count > 2 {
            appendText(start, end)
            return
        }
        let before = UnicodeClass.before(text, start)
        let after = UnicodeClass.after(text, end)
        let leftFlanking = !after.isWhitespace && (!after.isPunctuation || before.isWhitespace || before.isPunctuation)
        let rightFlanking = !before.isWhitespace && (!before.isPunctuation || after.isWhitespace || after.isPunctuation)
        var canOpen = leftFlanking
        var canClose = rightFlanking
        if character == UInt8(ascii: "_") {
            canOpen = leftFlanking && (!rightFlanking || before.isPunctuation)
            canClose = rightFlanking && (!leftFlanking || after.isPunctuation)
        }
        let node = appendNode(.text, scratch: start, length: count, payload: 1)
        guard canOpen || canClose else { return }
        delimiters.append(
            Delimiter(
                node: node, character: character, count: count, originalCount: count, canOpen: canOpen,
                canClose: canClose,
                previous: delimiterTop, next: -1))
        let index = Int32(delimiters.count - 1)
        if delimiterTop >= 0 { delimiters[Int(delimiterTop)].next = index }
        delimiterTop = index
    }

    mutating func removeDelimiter(_ index: Int32) {
        let delimiter = delimiters[Int(index)]
        if delimiter.previous >= 0 { delimiters[Int(delimiter.previous)].next = delimiter.next }
        if delimiter.next >= 0 {
            delimiters[Int(delimiter.next)].previous = delimiter.previous
        } else {
            delimiterTop = delimiter.previous
        }
    }

    /// Matches closers with openers above `bottom` (an index in the delimiter list, or -1) and wraps what lies between them (cmark's `process_emphasis`).
    mutating func processEmphasis(bottom: Int32) {
        guard delimiterTop != bottom else { return }
        for index in openersBottom.indices { openersBottom[index] = bottom }
        var closer = delimiterTop
        while delimiters[Int(closer)].previous != bottom { closer = delimiters[Int(closer)].previous }
        while closer >= 0 {
            guard spend() else { break }
            let current = delimiters[Int(closer)]
            guard current.canClose else {
                closer = current.next
                continue
            }
            let key = Self.kindIndex(current.character) * 6 + (current.canOpen ? 3 : 0) + current.originalCount % 3
            var opener = current.previous
            var found = false
            while opener >= 0, opener != bottom, opener != openersBottom[key] {
                guard spend() else { break }
                let candidate = delimiters[Int(opener)]
                let oddMatch =
                    (current.canOpen || candidate.canClose) && current.originalCount % 3 != 0
                    && (candidate.originalCount + current.originalCount) % 3 == 0
                if candidate.character == current.character, candidate.canOpen, !oddMatch,
                    current.character != UInt8(ascii: "~") || candidate.count == current.count
                {
                    found = true
                    break
                }
                opener = candidate.previous
            }
            if found, wrap(opener: opener, closer: closer) {
                if delimiters[Int(closer)].count == 0 {
                    let next = delimiters[Int(closer)].next
                    tree.unlink(current.node)
                    removeDelimiter(closer)
                    closer = next
                }
            } else {
                let next = current.next
                openersBottom[key] = current.previous
                if !current.canOpen { removeDelimiter(closer) }
                closer = next
            }
        }
        delimiterTop = bottom
        if bottom >= 0 { delimiters[Int(bottom)].next = -1 }
    }

    /// Wraps the nodes between a matched opener and closer in emphasis, strong emphasis or strikethrough. False if that would nest past the limit.
    private mutating func wrap(opener: Int32, closer: Int32) -> Bool {
        let open = delimiters[Int(opener)]
        let close = delimiters[Int(closer)]
        let used = close.character == UInt8(ascii: "~") ? close.count : (close.count >= 2 && open.count >= 2 ? 2 : 1)
        var height: Int32 = 0
        var node = tree.nodes[Int(open.node)].next
        while node != close.node {
            height = Swift.max(height, tree.nodes[Int(node)].height)
            node = tree.nodes[Int(node)].next
        }
        guard Int(height) + 1 <= limits.maxInlineDepth else {
            diagnostics.insert(.inlineDepthLimit)
            return false
        }
        delimiters[Int(opener)].count -= used
        delimiters[Int(closer)].count -= used
        tree.nodes[Int(open.node)].length -= used
        tree.nodes[Int(close.node)].start += used
        tree.nodes[Int(close.node)].length -= used

        let kind: NodeKind = close.character == UInt8(ascii: "~") ? .strikethrough : (used == 1 ? .emphasis : .strong)
        let container = Int32(tree.nodes.count)
        tree.nodes.append(InlineNode(kind: kind, height: height + 1))
        node = tree.nodes[Int(open.node)].next
        while node != close.node {
            let next = tree.nodes[Int(node)].next
            tree.unlink(node)
            tree.link(node, lastChildOf: container)
            node = next
        }
        tree.insert(container, after: open.node)
        delimiters[Int(opener)].next = closer
        delimiters[Int(closer)].previous = opener
        if delimiters[Int(opener)].count == 0 {
            tree.unlink(open.node)
            removeDelimiter(opener)
        }
        return true
    }
}
