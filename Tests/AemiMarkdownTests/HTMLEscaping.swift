/// The escapes the spec's reference HTML uses (cmark's `houdini`): text and attribute values, and `href` targets.
enum HTMLEscaping {
    static func text(_ bytes: some Sequence<UInt8>, into out: inout [UInt8]) {
        for byte in bytes {
            switch byte {
                case UInt8(ascii: "&"): out.append(contentsOf: Array("&amp;".utf8))
                case UInt8(ascii: "<"): out.append(contentsOf: Array("&lt;".utf8))
                case UInt8(ascii: ">"): out.append(contentsOf: Array("&gt;".utf8))
                case UInt8(ascii: "\""): out.append(contentsOf: Array("&quot;".utf8))
                default: out.append(byte)
            }
        }
    }

    /// A link target as cmark writes it: unreserved and sub-delimiter bytes stay, `&` and `'` become entities, the rest is percent-encoded.
    static func href(_ bytes: [UInt8], into out: inout [UInt8]) {
        let safe = Set(Array("-_.+!*(),%#@?=;:/,+$~".utf8))
        for byte in bytes {
            if byte.isASCIIAlphanumeric || safe.contains(byte) {
                out.append(byte)
            } else if byte == UInt8(ascii: "&") {
                out.append(contentsOf: Array("&amp;".utf8))
            } else if byte == UInt8(ascii: "'") {
                out.append(contentsOf: Array("&#x27;".utf8))
            } else {
                let digits = Array("0123456789ABCDEF".utf8)
                out.append(UInt8(ascii: "%"))
                out.append(digits[Int(byte >> 4)])
                out.append(digits[Int(byte & 15)])
            }
        }
    }
}

extension UInt8 {
    var isASCIIAlphanumeric: Bool {
        (self >= 0x30 && self <= 0x39) || (self >= 0x41 && self <= 0x5A) || (self >= 0x61 && self <= 0x7A)
    }
}
