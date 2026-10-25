/// The open and closing tags of CommonMark's raw HTML (6.6) and of HTML block condition 7, scanned within one line.
///
/// The grammar is regular, and the tests check these scanners against it with AemiRegex (ADR-0001).
enum HTMLTagScanner {
    typealias Bytes = ContiguousArray<UInt8>

    private static func isLetter(_ b: UInt8) -> Bool { (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) }
    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    private static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D }

    /// Whether `source[index ..< end]` is one complete open or closing tag (of a name other than the condition 1 names) followed only by spaces and tabs.
    static func completeTagFillsLine(_ source: Bytes, _ index: Int, _ end: Int) -> Bool {
        guard let tagEnd = tag(source, index, end) else { return false }
        var i = tagEnd
        while i < end, source[i] == 0x20 || source[i] == 0x09 { i += 1 }
        guard i == end else { return false }
        var nameStart = index + 1
        if source[nameStart] == UInt8(ascii: "/") { nameStart += 1 }
        var nameEnd = nameStart
        while nameEnd < end,
            isLetter(source[nameEnd]) || isDigit(source[nameEnd]) || source[nameEnd] == UInt8(ascii: "-")
        { nameEnd += 1 }
        let name = String(decoding: source[nameStart ..< nameEnd], as: UTF8.self).lowercased()
        return !["script", "style", "pre", "textarea"].contains(name)
    }

    /// The index after the open tag or closing tag at `index`, within `end`, or nil.
    static func tag(_ source: Bytes, _ index: Int, _ end: Int) -> Int? {
        guard index + 1 < end, source[index] == UInt8(ascii: "<") else { return nil }
        if source[index + 1] == UInt8(ascii: "/") { return closingTag(source, index, end) }
        return openTag(source, index, end)
    }

    private static func tagName(_ source: Bytes, _ start: Int, _ end: Int) -> Int? {
        guard start < end, isLetter(source[start]) else { return nil }
        var i = start + 1
        while i < end, isLetter(source[i]) || isDigit(source[i]) || source[i] == UInt8(ascii: "-") { i += 1 }
        return i
    }

    private static func closingTag(_ source: Bytes, _ index: Int, _ end: Int) -> Int? {
        guard var i = tagName(source, index + 2, end) else { return nil }
        while i < end, isSpace(source[i]) { i += 1 }
        guard i < end, source[i] == UInt8(ascii: ">") else { return nil }
        return i + 1
    }

    private static func openTag(_ source: Bytes, _ index: Int, _ end: Int) -> Int? {
        guard var i = tagName(source, index + 1, end) else { return nil }
        while true {
            let beforeSpace = i
            while i < end, isSpace(source[i]) { i += 1 }
            guard i < end else { return nil }
            if source[i] == UInt8(ascii: ">") { return i + 1 }
            if source[i] == UInt8(ascii: "/") {
                return i + 1 < end && source[i + 1] == UInt8(ascii: ">") ? i + 2 : nil
            }
            guard i > beforeSpace, let afterName = attributeName(source, i, end) else { return nil }
            i = afterName
            // an optional value: spaces, `=`, spaces, then an unquoted, single-quoted or double-quoted value
            var j = i
            while j < end, isSpace(source[j]) { j += 1 }
            if j < end, source[j] == UInt8(ascii: "=") {
                j += 1
                while j < end, isSpace(source[j]) { j += 1 }
                guard j < end, let afterValue = attributeValue(source, j, end) else { return nil }
                i = afterValue
            }
        }
    }

    private static func attributeName(_ source: Bytes, _ start: Int, _ end: Int) -> Int? {
        guard start < end,
            isLetter(source[start]) || source[start] == UInt8(ascii: "_") || source[start] == UInt8(ascii: ":")
        else { return nil }
        var i = start + 1
        while i < end,
            isLetter(source[i]) || isDigit(source[i])
                || [UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: ":"), UInt8(ascii: "-")].contains(source[i])
        { i += 1 }
        return i
    }

    private static func attributeValue(_ source: Bytes, _ start: Int, _ end: Int) -> Int? {
        let quote = source[start]
        if quote == UInt8(ascii: "'") || quote == UInt8(ascii: "\"") {
            var i = start + 1
            while i < end, source[i] != quote { i += 1 }
            return i < end ? i + 1 : nil
        }
        var i = start
        let forbidden: [UInt8] = [
            0x20, 0x09, 0x0A, 0x0C, 0x0D, UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "="), UInt8(ascii: "<"),
            UInt8(ascii: ">"), UInt8(ascii: "`")
        ]
        while i < end, !forbidden.contains(source[i]) { i += 1 }
        return i > start ? i : nil
    }
}
