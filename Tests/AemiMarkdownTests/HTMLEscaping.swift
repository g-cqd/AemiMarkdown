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

    /// GFM's tag filter: raw HTML as it is, except that the `<` of a few tags (the ones that can swallow the rest of a page or run a script) becomes `&lt;`.
    static func rawHTML(_ bytes: some Sequence<UInt8>, into out: inout [UInt8]) {
        let filtered = ["title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script", "plaintext"]
            .map { Array($0.utf8) }
        let all = Array(bytes)
        var i = 0
        while i < all.count {
            if all[i] == UInt8(ascii: "<") {
                var j = i + 1
                if j < all.count, all[j] == UInt8(ascii: "/") { j += 1 }
                let nameStart = j
                while j < all.count, all[j].isASCIIAlphanumeric { j += 1 }
                let name = all[nameStart ..< j].map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
                let ends = j == all.count || [0x20, 0x09, 0x0A, UInt8(ascii: ">"), UInt8(ascii: "/")].contains(all[j])
                if ends, filtered.contains(where: { $0 == name }) {
                    out.append(contentsOf: Array("&lt;".utf8))
                    i += 1
                    continue
                }
            }
            out.append(all[i])
            i += 1
        }
    }
}

extension UInt8 {
    var isASCIIAlphanumeric: Bool {
        (self >= 0x30 && self <= 0x39) || (self >= 0x41 && self <= 0x5A) || (self >= 0x61 && self <= 0x7A)
    }
}
