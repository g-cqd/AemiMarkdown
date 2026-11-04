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
