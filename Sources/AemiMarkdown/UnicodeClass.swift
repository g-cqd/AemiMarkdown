/// The two character classes CommonMark's emphasis rules use (6.2): Unicode whitespace, and Unicode punctuation (the P and S general categories).
///
/// ASCII is a table lookup. Anything else decodes one scalar and asks the standard library, which is the cold path: non-ASCII text next to a delimiter is rare.
enum UnicodeClass {
    struct Result {
        var isWhitespace: Bool
        var isPunctuation: Bool
    }

    /// The class of the character that ends just before `index`, or whitespace at the start of the text.
    static func before(_ text: ContiguousArray<UInt8>, _ index: Int) -> Result {
        guard index > 0 else { return Result(isWhitespace: true, isPunctuation: false) }
        let last = text[index - 1]
        if last < 0x80 { return ascii(last) }
        var start = index - 1
        while start > 0, index - start < 4, text[start] & 0xC0 == 0x80 { start -= 1 }
        return scalarClass(text, start, index)
    }

    /// The class of the character that starts at `index`, or whitespace at the end of the text.
    static func after(_ text: ContiguousArray<UInt8>, _ index: Int) -> Result {
        guard index < text.count else { return Result(isWhitespace: true, isPunctuation: false) }
        let first = text[index]
        if first < 0x80 { return ascii(first) }
        var end = index + 1
        while end < text.count, end - index < 4, text[end] & 0xC0 == 0x80 { end += 1 }
        return scalarClass(text, index, end)
    }

    private static func ascii(_ byte: UInt8) -> Result {
        Result(isWhitespace: ASCIIClass.isWhitespace(byte), isPunctuation: ASCIIClass.isPunctuation(byte))
    }

    private static func scalarClass(_ text: ContiguousArray<UInt8>, _ start: Int, _ end: Int) -> Result {
        var iterator = text[start ..< end].makeIterator()
        var decoder = UTF8()
        guard case .scalarValue(let scalar) = decoder.decode(&iterator) else {
            return Result(isWhitespace: false, isPunctuation: false)
        }
        switch scalar.properties.generalCategory {
            case .spaceSeparator: return Result(isWhitespace: true, isPunctuation: false)
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
                .finalPunctuation,
                .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
                return Result(isWhitespace: false, isPunctuation: true)
            default: return Result(isWhitespace: false, isPunctuation: false)
        }
    }
}
