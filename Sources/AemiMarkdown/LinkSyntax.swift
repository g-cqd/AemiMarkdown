/// The parts of a link that inline links and reference definitions share: label, destination and title (CommonMark 6.3 and 4.7), scanned in a text whose
/// lines are joined by line feeds. Each function takes the position, and moves it only when it finds what it looks for.
enum LinkSyntax {
    static let maxLabelLength = 999
    static let maxParenthesisDepth = 32

    /// Spaces, tabs and at most one line ending.
    static func skipSpaceAndOneNewline(_ text: ContiguousArray<UInt8>, _ position: inout Int) {
        var sawNewline = false
        while position < text.count {
            let byte = text[position]
            if byte == 0x20 || byte == 0x09 {
                position += 1
            } else if byte == 0x0A, !sawNewline {
                sawNewline = true
                position += 1
            } else {
                break
            }
        }
    }

    /// A link destination at the position, as a range of the text; the position moves past it. Nil leaves the position where it was.
    static func destination(_ text: ContiguousArray<UInt8>, _ position: inout Int) -> Range<Int>? {
        let start = position
        guard start < text.count else { return nil }
        if text[start] == UInt8(ascii: "<") {
            var index = start + 1
            while index < text.count {
                let byte = text[index]
                if byte == UInt8(ascii: ">") {
                    position = index + 1
                    return (start + 1) ..< index
                }
                if byte == 0x0A || byte == UInt8(ascii: "<") { return nil }
                if byte == UInt8(ascii: "\\"), index + 1 < text.count, ASCIIClass.isPunctuation(text[index + 1]) {
                    index += 1
                }
                index += 1
            }
            return nil
        }
        var index = start
        var depth = 0
        while index < text.count {
            let byte = text[index]
            if byte == UInt8(ascii: "\\"), index + 1 < text.count, ASCIIClass.isPunctuation(text[index + 1]) {
                index += 2
            } else if byte == UInt8(ascii: "(") {
                depth += 1
                if depth > maxParenthesisDepth { return nil }
                index += 1
            } else if byte == UInt8(ascii: ")") {
                if depth == 0 { break }
                depth -= 1
                index += 1
            } else if byte <= 0x20 || byte == 0x7F {
                break
            } else {
                index += 1
            }
        }
        guard depth == 0 else { return nil }
        position = index
        return start ..< index
    }

    /// A link title at the position: `"…"`, `'…'` or `(…)`. Nil leaves the position where it was.
    static func title(_ text: ContiguousArray<UInt8>, _ position: inout Int) -> Range<Int>? {
        let start = position
        guard start < text.count else { return nil }
        let open = text[start]
        let close: UInt8
        switch open {
            case UInt8(ascii: "\""), UInt8(ascii: "'"): close = open
            case UInt8(ascii: "("): close = UInt8(ascii: ")")
            default: return nil
        }
        var index = start + 1
        while index < text.count {
            let byte = text[index]
            if byte == UInt8(ascii: "\\"), index + 1 < text.count, ASCIIClass.isPunctuation(text[index + 1]) {
                index += 2
            } else if byte == close {
                position = index + 1
                return (start + 1) ..< index
            } else if open == UInt8(ascii: "("), byte == UInt8(ascii: "(") {
                return nil
            } else {
                index += 1
            }
        }
        return nil
    }

    /// The length of a link label `[…]` at the position, brackets included, or 0; the position moves past it when it matches.
    static func labelLength(_ text: ContiguousArray<UInt8>, _ position: inout Int) -> Int {
        let start = position
        guard start < text.count, text[start] == UInt8(ascii: "[") else { return 0 }
        var index = start + 1
        while index < text.count, index - start <= maxLabelLength {
            let byte = text[index]
            if byte == UInt8(ascii: "\\"), index + 1 < text.count, ASCIIClass.isPunctuation(text[index + 1]) {
                index += 2
            } else if byte == UInt8(ascii: "]") {
                position = index + 1
                return index + 1 - start
            } else if byte == UInt8(ascii: "[") {
                return 0
            } else {
                index += 1
            }
        }
        return 0
    }
}
