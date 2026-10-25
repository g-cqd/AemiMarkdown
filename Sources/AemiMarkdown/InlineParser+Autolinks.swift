extension InlineParser {
    /// A link found in a text node: where it starts and ends in the source, and how its target is made (the `autolink` payload).
    private struct Found {
        var start: Int
        var end: Int
        var payload: Int
    }

    /// GitHub's extended autolinks (`www.example.com`, `https://example.com`, `me@example.com`) in the text outside links and code, once emphasis is settled.
    mutating func autolinkBareLinks() {
        var stack: [Int32] = [InlineTree.root]
        while let parent = stack.popLast() {
            var child = tree.nodes[Int(parent)].firstChild
            while child >= 0 {
                let kind = tree.nodes[Int(child)].kind
                if kind == .text {
                    mergeTouchingText(into: child)
                    child = tree.nodes[Int(splitLinks(in: child))].next
                } else {
                    if Self.isContainer(kind), tree.nodes[Int(child)].firstChild >= 0 {
                        stack.append(child)
                    }
                    child = tree.nodes[Int(child)].next
                }
            }
        }
    }

    /// Whether the text has a byte that can start a bare link: `://`, `@`, or `www.`. Most leaf blocks have none, and then the pass over their nodes is skipped.
    func mayHoldBareLink() -> Bool {
        var index = 0
        while true {
            index = ByteScan.firstIndex(inSet: ByteScan.autolinkStarts, in: text, from: index)
            guard index < text.count else { return false }
            switch text[index] {
                case UInt8(ascii: "@"): return true
                case UInt8(ascii: ":"):
                    if index + 2 < text.count, text[index + 1] == 0x2F, text[index + 2] == 0x2F { return true }
                default:
                    if index + 3 < text.count, text[index + 1] == 0x77, text[index + 2] == 0x77, text[index + 3] == 0x2E
                    {
                        return true
                    }
            }
            index += 1
        }
    }

    private static func isContainer(_ kind: NodeKind) -> Bool {
        kind == .emphasis || kind == .strong || kind == .strikethrough
    }

    /// Text that touches the text after it is one run, as it would have been written: emphasis delimiters that stayed text join it.
    private mutating func mergeTouchingText(into node: Int32) {
        var next = tree.nodes[Int(node)].next
        while next >= 0, tree.nodes[Int(next)].kind == .text,
            tree.nodes[Int(node)].start + tree.nodes[Int(node)].length == tree.nodes[Int(next)].start
        {
            tree.nodes[Int(node)].length += tree.nodes[Int(next)].length
            let after = tree.nodes[Int(next)].next
            tree.unlink(next)
            next = after
        }
    }

    /// Replaces the text node by text and autolinks if it holds any link. Returns the last node of the replacement (the node itself if none).
    private mutating func splitLinks(in node: Int32) -> Int32 {
        let start = tree.nodes[Int(node)].start
        let length = tree.nodes[Int(node)].length
        var found: [Found] = []
        var index = 0
        while index < length {
            var match: Found?
            switch source[start + index] {
                case UInt8(ascii: "w"): match = wwwLink(at: start + index, start, start + length)
                case UInt8(ascii: ":"): match = schemeLink(at: start + index, start, start + length)
                case UInt8(ascii: "@"): match = emailLink(at: start + index, start, start + length)
                default: break
            }
            if let match, match.start >= (found.last?.end ?? start) {
                found.append(match)
                index = match.end - start
            } else {
                index += 1
            }
        }
        guard let first = found.first else { return node }
        // The node keeps the text before the first link; the rest is inserted after it.
        tree.nodes[Int(node)].length = first.start - start
        var anchor = node
        var cursor = first.start
        for link in found {
            if link.start > cursor { anchor = insertText(cursor, link.start, after: anchor) }
            let container = Int32(tree.nodes.count)
            tree.nodes.append(InlineNode(kind: .autolink, payload: link.payload, height: 1))
            tree.insert(container, after: anchor)
            tree.append(InlineNode(kind: .text, start: link.start, length: link.end - link.start), to: container)
            anchor = container
            cursor = link.end
        }
        if cursor < start + length { anchor = insertText(cursor, start + length, after: anchor) }
        return anchor
    }

    private mutating func insertText(_ from: Int, _ to: Int, after anchor: Int32) -> Int32 {
        let index = Int32(tree.nodes.count)
        tree.nodes.append(InlineNode(kind: .text, start: from, length: to - from))
        tree.insert(index, after: anchor)
        return index
    }

    // MARK: - Matching, after cmark-gfm's autolink extension

    // @dl:disable near-clone -- the three forms of an extended autolink are three functions that mirror cmark-gfm's, one rule each
    private func isSpace(_ byte: UInt8) -> Bool { ASCIIClass.isWhitespace(byte) }

    /// `www.` after the start of the text, a space, or one of `*_~(`; then a domain with a dot.
    private func wwwLink(at index: Int, _ lower: Int, _ upper: Int) -> Found? {
        guard upper - index >= 4, source[index + 1] == UInt8(ascii: "w"), source[index + 2] == UInt8(ascii: "w"),
            source[index + 3] == UInt8(ascii: ".")
        else {
            return nil
        }
        if index > lower {
            let before = source[index - 1]
            guard
                isSpace(before)
                    || [UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "(")].contains(before)
            else { return nil }
        }
        guard let domainEnd = domain(source, index, upper, allowShort: false) else { return nil }
        let end = trimmed(from: index, pathEnd(domainEnd, upper))
        return end > index ? Found(start: index, end: end, payload: 2) : nil
    }

    /// `http://`, `https://` or `ftp://` and a domain.
    private func schemeLink(at index: Int, _ lower: Int, _ upper: Int) -> Found? {
        guard upper - index >= 4, source[index + 1] == UInt8(ascii: "/"), source[index + 2] == UInt8(ascii: "/") else {
            return nil
        }
        var start = index
        while start > lower, ASCIIClass.isLetter(source[start - 1]) { start -= 1 }
        let scheme = String(decoding: source[start ..< index], as: UTF8.self).lowercased()
        guard ["http", "https", "ftp"].contains(scheme) else { return nil }
        guard let domainEnd = domain(source, index + 3, upper, allowShort: true) else { return nil }
        let end = trimmed(from: start, pathEnd(domainEnd, upper))
        return end > index + 3 ? Found(start: start, end: end, payload: 0) : nil
    }

    // @dl:enable near-clone
    /// `local@domain`, where the domain has a dot, optionally after `mailto:` or `xmpp:`.
    private func emailLink(at index: Int, _ lower: Int, _ upper: Int) -> Found? {
        var start = index
        while start > lower,
            ASCIIClass.isAlphanumeric(source[start - 1])
                || [0x2E, 0x2B, 0x2D, 0x5F].contains(source[start - 1])
        {
            start -= 1
        }
        guard start < index else { return nil }
        var end = index + 1
        var dots = 0
        while end < upper {
            let byte = source[end]
            if ASCIIClass.isAlphanumeric(byte) {
                end += 1
            } else if byte == UInt8(ascii: "."), end + 1 < upper,
                ASCIIClass.isAlphanumeric(source[end + 1])
            {
                dots += 1
                end += 1
            } else if byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") {
                end += 1
            } else {
                break
            }
        }
        guard dots > 0, end - index >= 2, ASCIIClass.isLetter(source[end - 1]) || source[end - 1] == UInt8(ascii: ".")
        else { return nil }
        var payload = 1
        for prefix in ["mailto:", "xmpp:"] {
            let bytes = Array(prefix.utf8)
            let before = start - bytes.count - 1
            if start - lower >= bytes.count, source[(start - bytes.count) ..< start].elementsEqual(bytes),
                before < lower || !(ASCIIClass.isAlphanumeric(source[before]))
            {
                start -= bytes.count
                payload = 0
                if prefix == "xmpp:", end < upper, source[end] == UInt8(ascii: "/") {
                    end = pathEnd(end, upper)
                }
            }
        }
        end = trimmed(from: start, end)
        return end > index ? Found(start: start, end: end, payload: payload) : nil
    }

    /// The end of a valid domain that starts at `index`: letters, digits and hyphens, dots between, no underscore in the last two parts.
    private func domain(_ bytes: ContiguousArray<UInt8>, _ index: Int, _ upper: Int, allowShort: Bool) -> Int? {
        var i = index + (allowShort ? 0 : 1)
        var dots = 0
        var underscoresBefore = 0
        var underscores = 0
        while i < upper {
            let byte = bytes[i]
            if byte == UInt8(ascii: "_") {
                underscores += 1
            } else if byte == UInt8(ascii: ".") {
                underscoresBefore = underscores
                underscores = 0
                dots += 1
            } else if !(ASCIIClass.isAlphanumeric(byte)) && byte != UInt8(ascii: "-")
                && byte < 0x80
            {
                break
            }
            i += 1
        }
        if underscoresBefore > 0 || underscores > 0 { return nil }
        return allowShort ? (i > index ? i : nil) : (dots > 0 ? i : nil)
    }

    /// Everything up to a space or `<`.
    private func pathEnd(_ from: Int, _ upper: Int) -> Int {
        var end = from
        while end < upper, !isSpace(source[end]), source[end] != UInt8(ascii: "<") { end += 1 }
        return end
    }

    /// Takes trailing punctuation, an unbalanced `)` and an entity-like `&…;` off the end of a link that starts at `start`.
    /// - Complexity: O(link length): the parentheses are counted once and then adjusted as the end moves.
    private func trimmed(from start: Int, _ end: Int) -> Int {
        var end = end
        var open = 0
        var close = 0
        for byte in source[start ..< end] {
            if byte == UInt8(ascii: "(") { open += 1 } else if byte == UInt8(ascii: ")") { close += 1 }
        }
        while end > start {
            let last = source[end - 1]
            if Self.isTrailingPunctuation(last) {
                end -= 1
            } else if last == UInt8(ascii: ";") {
                var scan = end - 2
                while scan > start, ASCIIClass.isLetter(source[scan]) { scan -= 1 }
                end = scan < end - 2 && source[scan] == UInt8(ascii: "&") ? scan : end - 1
            } else if last == UInt8(ascii: ")") {
                if close <= open { break }
                close -= 1
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static func isTrailingPunctuation(_ byte: UInt8) -> Bool {
        switch byte {
            case UInt8(ascii: "?"), UInt8(ascii: "!"), UInt8(ascii: "."), UInt8(ascii: ","), UInt8(ascii: ":"),
                UInt8(ascii: "*"),
                UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "'"), UInt8(ascii: "\""):
                true
            default: false
        }
    }
}
