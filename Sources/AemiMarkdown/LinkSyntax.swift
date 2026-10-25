/// The parts of a link that inline links and reference definitions share: label, destination and title (CommonMark 6.3 and 4.7), scanned in a text whose
/// lines are joined by line feeds. Each function takes the position, and moves it only when it finds what it looks for.
enum LinkSyntax {
    static let maxLabelLength = 999
    static let maxParenthesisDepth = 32

    /// What a scan costs and whether it stopped at a limit, for the caller to charge to its budget and to report.
    struct Scan {
        /// The bytes looked at, found or not: a title with no end is read to the end of the text, each time a `(` offers one.
        var bytes = 0
        /// A destination or title was longer than the limit, and so is not one.
        var tooLong = false
    }

    /// The length of a backslash escape (a backslash and the ASCII punctuation after it) at `index`, or 0.
    @inline(__always)
    private static func escapeLength(_ text: ContiguousArray<UInt8>, _ index: Int) -> Int {
        text[index] == UInt8(ascii: "\\") && index + 1 < text.count && ASCIIClass.isPunctuation(text[index + 1]) ? 2 : 0
    }

    // @dl:disable near-clone -- the destination and the title are two grammars in one loop shell: a limit check, a count, an escape; one loop with a callback would put an indirect call in the hot byte loop
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

    /// A link destination at the position, as a range of the text, at most `limit` bytes long; the position moves past it. Nil leaves the position where it was.
    static func destination(
        _ text: ContiguousArray<UInt8>, _ position: inout Int, limit: Int, _ scan: inout Scan
    ) -> Range<Int>? {
        let start = position
        guard start < text.count else { return nil }
        let bracketed = text[start] == UInt8(ascii: "<")
        var index = bracketed ? start + 1 : start
        var depth = 0
        while index < text.count {
            if index - start > limit {
                scan.tooLong = true
                return nil
            }
            scan.bytes += 1
            let byte = text[index]
            let escape = escapeLength(text, index)
            if escape > 0 {
                index += escape
            } else if bracketed {
                if byte == UInt8(ascii: ">") {
                    position = index + 1
                    return (start + 1) ..< index
                }
                if byte == 0x0A || byte == UInt8(ascii: "<") { return nil }
                index += 1
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
        guard !bracketed, depth == 0 else { return nil }
        position = index
        return start ..< index
    }

    /// A link title at the position: `"…"`, `'…'` or `(…)`, at most `limit` bytes long. Nil leaves the position where it was.
    static func title(
        _ text: ContiguousArray<UInt8>, _ position: inout Int, limit: Int, _ scan: inout Scan
    ) -> Range<Int>? {
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
            if index - start > limit {
                scan.tooLong = true
                return nil
            }
            scan.bytes += 1
            let escape = escapeLength(text, index)
            if escape > 0 {
                index += escape
            } else if text[index] == close {
                position = index + 1
                return (start + 1) ..< index
            } else if open == UInt8(ascii: "("), text[index] == UInt8(ascii: "(") {
                return nil
            } else {
                index += 1
            }
        }
        return nil
    }

    // @dl:enable near-clone
    /// The length of a link label `[…]` at the position, brackets included, or 0; the position moves past it when it matches.
    static func labelLength(_ text: ContiguousArray<UInt8>, _ position: inout Int) -> Int {
        let start = position
        guard start < text.count, text[start] == UInt8(ascii: "[") else { return 0 }
        var index = start + 1
        while index < text.count, index - start <= maxLabelLength {
            let escape = escapeLength(text, index)
            if escape > 0 {
                index += escape
            } else if text[index] == UInt8(ascii: "]") {
                position = index + 1
                return index + 1 - start
            } else if text[index] == UInt8(ascii: "[") {
                return 0
            } else {
                index += 1
            }
        }
        return 0
    }
}
