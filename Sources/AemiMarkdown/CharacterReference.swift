/// Decoding of `&#35;`, `&#x23;` and named references.
enum CharacterReference {
    /// The scalars of the reference that starts at `index` (a `&`), and its length in bytes including the `;`, or nil if none starts there.
    static func decode(_ bytes: ContiguousArray<UInt8>, at index: Int, end: Int) -> ([Unicode.Scalar], Int)? {
        guard index + 2 < end, bytes[index + 1] == UInt8(ascii: "#") else { return nil }
        var i = index + 2
        let hex = bytes[i] == UInt8(ascii: "x") || bytes[i] == UInt8(ascii: "X")
        if hex { i += 1 }
        var value: UInt32 = 0
        var digits = 0
        while i < end, let digit = Self.digit(bytes[i], hex: hex) {
            guard digits < (hex ? 6 : 7) else { return nil }
            value = value * (hex ? 16 : 10) + digit
            digits += 1
            i += 1
        }
        guard digits > 0, i < end, bytes[i] == UInt8(ascii: ";") else { return nil }
        let scalar = value == 0 ? Unicode.Scalar(0xFFFD) : Unicode.Scalar(value)
        return ([scalar ?? Unicode.Scalar(0xFFFD) ?? " "], i + 1 - index)
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
