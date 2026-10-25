extension InlineParser {
    /// A `<`: an autolink, raw inline HTML, or the character itself (CommonMark 6.5 and 6.6).
    mutating func angle() {
        let start = position
        if let (end, kind) = Self.autolink(text, at: start) {
            let container = tree.append(InlineNode(kind: .autolink, payload: kind, height: 1))
            tree.append(InlineNode(kind: .text, start: sourceOffset(start + 1), length: end - start - 2), to: container)
            position = end
        } else if let end = Self.rawHTMLEnd(text, at: start) {
            appendPieces(.htmlInline, from: start, to: end)
            position = end
        } else {
            appendText(start, start + 1)
            position += 1
        }
    }

    /// Adds `text[from ..< to]` as leaves of `kind`, one per line, with a soft break between lines.
    private mutating func appendPieces(_ kind: NodeKind, from: Int, to: Int) {
        var lineStart = from
        for index in from ..< to where text[index] == 0x0A {
            tree.append(InlineNode(kind: kind, start: sourceOffset(lineStart), length: index - lineStart))
            tree.append(InlineNode(kind: .softBreak))
            lineStart = index + 1
        }
        tree.append(InlineNode(kind: kind, start: sourceOffset(lineStart), length: to - lineStart))
    }

    /// The index after an autolink that starts at `index` (`<`), and its kind: 0 for a URI, 1 for an email address.
    static func autolink(_ text: ContiguousArray<UInt8>, at index: Int) -> (Int, Int)? {
        var i = index + 1
        guard i < text.count, ASCIIClass.isLetter(text[i]) else { return emailAutolink(text, at: index) }
        let schemeStart = i
        while i < text.count,
            ASCIIClass.isAlphanumeric(text[i]) || [0x2B, 0x2E, 0x2D].contains(text[i])
        { i += 1 }
        guard i - schemeStart >= 2, i - schemeStart <= 32, i < text.count, text[i] == UInt8(ascii: ":") else {
            return emailAutolink(text, at: index)
        }
        i += 1
        while i < text.count {
            let byte = text[i]
            if byte == UInt8(ascii: ">") { return (i + 1, 0) }
            if byte <= 0x20 || byte == UInt8(ascii: "<") || byte == 0x7F { break }
            i += 1
        }
        return emailAutolink(text, at: index)
    }

    private static func emailAutolink(_ text: ContiguousArray<UInt8>, at index: Int) -> (Int, Int)? {
        var i = index + 1
        let local = i
        let allowed = Array("!#$%&'*+/=?^_`{|}~-.".utf8)
        while i < text.count, ASCIIClass.isAlphanumeric(text[i]) || allowed.contains(text[i]) {
            i += 1
        }
        guard i > local, i < text.count, text[i] == UInt8(ascii: "@") else { return nil }
        i += 1
        // domain labels: 1 to 63 letters, digits and hyphens, not starting or ending with a hyphen, separated by dots
        while true {
            let labelStart = i
            while i < text.count,
                ASCIIClass.isAlphanumeric(text[i]) || text[i] == UInt8(ascii: "-")
            { i += 1 }
            let length = i - labelStart
            guard length >= 1, length <= 63, text[labelStart] != UInt8(ascii: "-"), text[i - 1] != UInt8(ascii: "-")
            else { return nil }
            if i < text.count, text[i] == UInt8(ascii: ".") {
                i += 1
                continue
            }
            break
        }
        guard i < text.count, text[i] == UInt8(ascii: ">") else { return nil }
        return (i + 1, 1)
    }

    /// The index after a raw HTML construct that starts at `index` (`<`): an open or closing tag, a comment, a processing instruction, a declaration or CDATA.
    static func rawHTMLEnd(_ text: ContiguousArray<UInt8>, at index: Int) -> Int? {
        guard index + 1 < text.count else { return nil }
        func find(_ needle: String, from: Int) -> Int? {
            let bytes = Array(needle.utf8)
            guard text.count - from >= bytes.count else { return nil }
            var i = from
            while i + bytes.count <= text.count {
                if text[i] == bytes[0], text[i ..< (i + bytes.count)].elementsEqual(bytes) { return i + bytes.count }
                i += 1
            }
            return nil
        }
        func starts(_ prefix: String) -> Bool {
            let bytes = Array(prefix.utf8)
            return index + bytes.count <= text.count && text[index ..< (index + bytes.count)].elementsEqual(bytes)
        }
        switch text[index + 1] {
            case UInt8(ascii: "!"):
                if starts("<!-->") { return index + 5 }
                if starts("<!--->") { return index + 6 }
                if starts("<!--") { return find("-->", from: index + 4) }
                if starts("<![CDATA[") { return find("]]>", from: index + 9) }
                if index + 2 < text.count, ASCIIClass.isLetter(text[index + 2]) { return find(">", from: index + 2) }
                return nil
            case UInt8(ascii: "?"): return find("?>", from: index + 2)
            default: return HTMLTagScanner.tag(text, index, text.count)
        }
    }
}
