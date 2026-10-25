/// The seven start conditions of an HTML block, and the five end conditions (CommonMark 4.6).
enum HTMLBlockScanner {
    typealias Bytes = ContiguousArray<UInt8>

    /// The block tag names of condition 6, lowercase and sorted, so a name is found by binary search.
    // @dl:disable near-clone -- a table of tag names: rows of one shape, by design
    private static let blockNames: [[UInt8]] = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup",
        "dd", "details",
        "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
        "h1", "h2", "h3", "h4",
        "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav",
        "noframes", "ol",
        "optgroup", "option", "p", "param", "search", "section", "summary", "table", "tbody", "td", "tfoot", "th",
        "thead", "title", "tr",
        "track", "ul"
    ]
    .map { Array($0.utf8) }
    // @dl:enable near-clone

    private static func lower(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }

    private static func hasPrefixIgnoringCase(_ source: Bytes, _ index: Int, _ end: Int, _ prefix: String) -> Bool {
        var i = index
        for byte in prefix.utf8 {
            guard i < end, lower(source[i]) == byte else { return false }
            i += 1
        }
        return true
    }

    /// The condition (1 to 7) of the HTML block that starts at `index`, or nil. Condition 7 cannot interrupt a paragraph.
    static func startCondition(_ source: Bytes, _ index: Int, _ end: Int, interruptsParagraph: Bool) -> Int? {
        guard index < end, source[index] == UInt8(ascii: "<") else { return nil }
        for name in ["script", "pre", "style", "textarea"] where hasPrefixIgnoringCase(source, index + 1, end, name) {
            let after = index + 1 + name.utf8.count
            if after == end || [0x20, 0x09, UInt8(ascii: ">")].contains(source[after]) { return 1 }
        }
        if hasPrefixIgnoringCase(source, index, end, "<!--") { return 2 }
        if hasPrefixIgnoringCase(source, index, end, "<?") { return 3 }
        if hasPrefixIgnoringCase(source, index, end, "<![cdata[") { return 5 }
        if index + 2 < end, source[index + 1] == UInt8(ascii: "!"), isASCIILetter(source[index + 2]) { return 4 }
        var i = index + 1
        if i < end, source[i] == UInt8(ascii: "/") { i += 1 }
        let nameStart = i
        while i < end, isASCIILetter(source[i]) || (i > nameStart && source[i] >= 0x30 && source[i] <= 0x39) { i += 1 }
        if i > nameStart {
            let name = source[nameStart ..< i].map(lower)
            let followed =
                i == end || source[i] == 0x20 || source[i] == 0x09 || source[i] == UInt8(ascii: ">")
                || (source[i] == UInt8(ascii: "/") && i + 1 < end && source[i + 1] == UInt8(ascii: ">"))
            if followed, blockNames.contains(where: { $0 == name }) { return 6 }
        }
        if !interruptsParagraph, HTMLTagScanner.completeTagFillsLine(source, index, end) { return 7 }
        return nil
    }

    /// Whether `condition` (1 to 5) ends on this line. Conditions 6 and 7 end at a blank line, which the caller sees.
    static func ends(_ condition: Int, _ source: Bytes, _ index: Int, _ end: Int) -> Bool {
        func contains(_ needle: String, ignoringCase: Bool = false) -> Bool {
            let length = needle.utf8.count
            guard end - index >= length else { return false }
            for start in index ... (end - length) {
                var matches = true
                var k = start
                for byte in needle.utf8 {
                    let value = ignoringCase ? lower(source[k]) : source[k]
                    if value != byte {
                        matches = false
                        break
                    }
                    k += 1
                }
                if matches { return true }
            }
            return false
        }
        switch condition {
            case 1:
                return ["</script>", "</pre>", "</style>", "</textarea>"].contains { contains($0, ignoringCase: true) }
            case 2: return contains("-->")
            case 3: return contains("?>")
            case 4: return contains(">")
            case 5: return contains("]]>")
            default: return false
        }
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }
}
