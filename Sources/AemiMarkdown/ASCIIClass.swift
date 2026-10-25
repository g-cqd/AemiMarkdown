/// Byte classes the CommonMark rules are written in terms of.
enum ASCIIClass {
    /// ASCII punctuation: the 32 characters `!` to `/`, `:` to `@`, `[` to a backtick, and `{` to `~`.
    @inline(__always)
    static func isPunctuation(_ byte: UInt8) -> Bool {
        (byte >= 0x21 && byte <= 0x2F) || (byte >= 0x3A && byte <= 0x40) || (byte >= 0x5B && byte <= 0x60)
            || (byte >= 0x7B && byte <= 0x7E)
    }

    /// Space, tab, line feed, form feed and carriage return: CommonMark's "whitespace character" in the ASCII range.
    @inline(__always)
    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    @inline(__always)
    static func isLetter(_ byte: UInt8) -> Bool { (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) }

    @inline(__always)
    static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    @inline(__always)
    static func isAlphanumeric(_ byte: UInt8) -> Bool { isLetter(byte) || isDigit(byte) }

    /// Whether `bytes` is the lowercase ASCII word `lowercase`, ignoring the case of `bytes`. Allocates nothing.
    static func equalsIgnoringCase(_ bytes: some Collection<UInt8>, _ lowercase: StaticString) -> Bool {
        guard bytes.count == lowercase.utf8CodeUnitCount else { return false }
        var index = 0
        for byte in bytes {
            let folded = byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
            // SAFETY: `index` is below the literal's length, which equals `bytes.count`.
            let expected = unsafe lowercase.utf8Start[index]
            guard folded == expected else { return false }
            index += 1
        }
        return true
    }
}
