/// Text and URLs made safe for HTML (ADR 0007): what a document says is never markup.
enum HTMLText {
    /// `text` for an element's content or a quoted attribute: the five characters HTML reserves are escaped and the scalars a page should not carry (controls other than white space,
    /// bidirectional controls, noncharacters) are dropped.
    static func escaped(_ text: some Sequence<Unicode.Scalar>) -> String {
        var result = ""
        for scalar in text {
            switch scalar.value {
                case 0x26: result += "&amp;"
                case 0x3C: result += "&lt;"
                case 0x3E: result += "&gt;"
                case 0x22: result += "&quot;"
                case 0x27: result += "&#39;"
                case 0x09, 0x0A, 0x20 ... 0x7E, 0xA0 ... 0x061B, 0x061D ... 0x200D, 0x2010 ... 0x2029,
                    0x202F ... 0x2065, 0x206A ... 0xFDCF, 0xFDF0 ... 0xFEFE, 0xFF00 ... 0xFFFD,
                    0x10000 ... 0x10FFFF:
                    result.unicodeScalars.append(scalar)
                default: continue
            }
        }
        return result
    }

    static func escaped(_ text: String) -> String { escaped(text.unicodeScalars) }

    /// `isSafeDestination` on the bytes of a destination, without making a `String` of them when they are ASCII (nearly always); the scheme is compared without regard to case.
    static func isSafeDestination(bytes: [UInt8]) -> Bool {
        if bytes.contains(where: { $0 >= 0x80 }) { return isSafeDestination(String(decoding: bytes, as: UTF8.self)) }
        var scheme: [UInt8] = []
        for byte in bytes {
            if byte <= 0x20 {
                guard scheme.isEmpty || byte == 0x09 || byte == 0x0A || byte == 0x0D else { break }
                continue
            }
            if byte == 0x3A {
                switch scheme.count {
                    case 4: return scheme.elementsEqual("http".utf8, by: { $0 | 0x20 == $1 })
                    case 5: return scheme.elementsEqual("https".utf8, by: { $0 | 0x20 == $1 })
                    case 6: return scheme.elementsEqual("mailto".utf8, by: { $0 | 0x20 == $1 })
                    default: return false
                }
            }
            if byte == 0x2F || byte == 0x3F || byte == 0x23 { return true }
            scheme.append(byte)
            if scheme.count > 16 { return true }
        }
        return true
    }

    /// A destination a link may carry: `http`, `https`, `mailto`, a fragment, or a relative reference. Anything with another scheme (`javascript:`, `data:`, `file:`, `vbscript:`) is not a link.
    /// The scheme is read as a browser reads it: leading control characters and white space are skipped and tabs and line feeds inside it are ignored.
    static func isSafeDestination(_ destination: String) -> Bool {
        var scheme = ""
        for scalar in destination.unicodeScalars {
            if scalar.value <= 0x20 {
                guard scheme.isEmpty || scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D else {
                    break
                }
                continue
            }
            if scalar == ":" { return ["http", "https", "mailto"].contains(scheme.lowercased()) }
            // A path, a query or a fragment before any colon: relative.
            if scalar == "/" || scalar == "?" || scalar == "#" { return true }
            scheme.unicodeScalars.append(scalar)
            // No scheme is this long: a relative reference.
            if scheme.unicodeScalars.count > 16 { return true }
        }
        return true
    }
}
