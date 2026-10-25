/// Character references: `&#35;`, `&#x23;` and the HTML5 names such as `&amp;`.
enum CharacterReference {
    /// The scalars of the reference that starts at `index` (a `&`) and its length in bytes, `;` included, or nil if no valid reference starts there.
    static func decode(_ bytes: ContiguousArray<UInt8>, at index: Int, end: Int) -> ([Unicode.Scalar], Int)? {
        guard index + 2 < end else { return nil }
        if bytes[index + 1] == UInt8(ascii: "#") { return numeric(bytes, at: index, end: end) }
        var i = index + 1
        while i < end, i - index <= EntityTable.maxNameLength + 1, isNameByte(bytes[i]) { i += 1 }
        guard i < end, bytes[i] == UInt8(ascii: ";"), let scalars = EntityTable.lookup(bytes[(index + 1) ..< i]) else {
            return nil
        }
        return (scalars, i + 1 - index)
    }

    /// The length of the reference that starts at `index` in `bytes`, or nil.
    static func length(_ bytes: ContiguousArray<UInt8>, at index: Int) -> Int? {
        decode(bytes, at: index, end: bytes.count)?.1
    }

    private static func numeric(_ bytes: ContiguousArray<UInt8>, at index: Int, end: Int) -> ([Unicode.Scalar], Int)? {
        var i = index + 2
        let hex = i < end && (bytes[i] == UInt8(ascii: "x") || bytes[i] == UInt8(ascii: "X"))
        if hex { i += 1 }
        var value: UInt32 = 0
        var digits = 0
        while i < end, let digit = digit(bytes[i], hex: hex) {
            guard digits < (hex ? 6 : 7) else { return nil }
            value = value * (hex ? 16 : 10) + digit
            digits += 1
            i += 1
        }
        guard digits > 0, i < end, bytes[i] == UInt8(ascii: ";") else { return nil }
        // NUL, surrogates and anything past U+10FFFF stand for U+FFFD.
        let scalar = value == 0 ? nil : Unicode.Scalar(value)
        return ([scalar ?? "\u{FFFD}"], i + 1 - index)
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    private static func digit(_ byte: UInt8, hex: Bool) -> UInt32? {
        switch byte {
            case 0x30 ... 0x39: return UInt32(byte - 0x30)
            case 0x61 ... 0x66 where hex: return UInt32(byte - 0x61 + 10)
            case 0x41 ... 0x46 where hex: return UInt32(byte - 0x41 + 10)
            default: return nil
        }
    }
}
