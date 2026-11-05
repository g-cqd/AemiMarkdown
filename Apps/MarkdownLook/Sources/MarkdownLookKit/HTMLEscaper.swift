internal import AemiKernels

/// `HTMLText.escaped` on bytes, in one pass: the text of the source goes to the output buffer without becoming a `String` or being read a scalar at a time. A run of plain ASCII is copied whole; the five reserved characters are
/// written as references; the scalars a page should not carry are dropped (the same ones `HTMLText.escaped` drops); a byte sequence that is not UTF-8 becomes U+FFFD, one for each maximal ill-formed subpart, as
/// `String(decoding:as:)` would have made it. With smart punctuation on, the same pass makes the curly quotes and the ellipsis (`SmartPunctuation`'s rules, with its state carried across calls).
enum HTMLEscaper {
    /// For each byte: 0 if it is copied as it is, 1 if the pass has to look at it. Bytes above 0x7F, controls, the five reserved characters; with smart punctuation also the full stop.
    private static let plainClasses: [UInt8] = classes(smart: false)
    private static let smartClasses: [UInt8] = classes(smart: true)

    /// The same bytes as a set for the SIMD scan: every byte above 0x7F, the controls except tab and line feed, DEL, the five reserved characters, and with smart punctuation the full stop. Five rows of nibbles, so the tables hold it exactly.
    private static let plainSet = byteSet(smart: false)
    private static let smartSet = byteSet(smart: true)

    private static func byteSet(smart: Bool) -> AemiKernels.ByteSet {
        let bytes = (0 ..< 256).filter { (smart ? smartClasses : plainClasses)[$0] != 0 }.map { UInt8($0) }
        guard let set = AemiKernels.ByteSet(bytes) else {
            preconditionFailure("the escaper's bytes do not fit nibble tables")
        }
        return set
    }

    private static func classes(smart: Bool) -> [UInt8] {
        (0 ..< 256)
            .map { byte in
                switch byte {
                    case 0x09, 0x0A: 0
                    case 0x00 ... 0x1F, 0x7F ... 0xFF, 0x26, 0x3C, 0x3E, 0x22, 0x27: 1
                    case 0x2E: smart ? 1 : 0
                    default: 0
                }
            }
    }

    /// Whether a page may carry the scalar (the ranges `HTMLText.escaped` keeps): tab, line feed, the printable ASCII, and from U+00A0 up everything but the C1 controls, the bidirectional controls, the byte order mark, and the noncharacters.
    static func isAllowed(_ value: UInt32) -> Bool {
        switch value {
            case 0x09, 0x0A, 0x20 ... 0x7E, 0xA0 ... 0x061B, 0x061D ... 0x200D, 0x2010 ... 0x2029, 0x202F ... 0x2065,
                0x206A ... 0xFDCF, 0xFDF0 ... 0xFEFE, 0xFF00 ... 0xFFFD, 0x10000 ... 0x10FFFF:
                true
            default: false
        }
    }

    /// The scalar that starts at `index` and how many bytes it takes; for ill-formed input, U+FFFD and the length of the maximal ill-formed subpart (at least one byte).
    @inline(__always)
    private static func decode(_ bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> (value: UInt32, length: Int) {
        let count = bytes.count
        let lead = UInt32(unsafe bytes[index])
        func continuation(_ offset: Int, _ low: UInt8 = 0x80, _ high: UInt8 = 0xBF) -> UInt32? {
            guard index + offset < count else { return nil }
            let byte = unsafe bytes[index + offset]
            return byte >= low && byte <= high ? UInt32(byte & 0x3F) : nil
        }
        switch lead {
            case 0xC2 ... 0xDF:
                guard let second = continuation(1) else { return (0xFFFD, 1) }
                return ((lead & 0x1F) << 6 | second, 2)
            case 0xE0 ... 0xEF:
                let low: UInt8 = lead == 0xE0 ? 0xA0 : 0x80
                let high: UInt8 = lead == 0xED ? 0x9F : 0xBF
                guard let second = continuation(1, low, high) else { return (0xFFFD, 1) }
                guard let third = continuation(2) else { return (0xFFFD, 2) }
                return ((lead & 0x0F) << 12 | second << 6 | third, 3)
            case 0xF0 ... 0xF4:
                let low: UInt8 = lead == 0xF0 ? 0x90 : 0x80
                let high: UInt8 = lead == 0xF4 ? 0x8F : 0xBF
                guard let second = continuation(1, low, high) else { return (0xFFFD, 1) }
                guard let third = continuation(2) else { return (0xFFFD, 2) }
                guard let fourth = continuation(3) else { return (0xFFFD, 3) }
                return ((lead & 0x07) << 18 | second << 12 | third << 6 | fourth, 4)
            default: return (0xFFFD, 1)
        }
    }

    private static let ampersand = Array("&amp;".utf8)
    private static let lessThan = Array("&lt;".utf8)
    private static let greaterThan = Array("&gt;".utf8)
    private static let quote = Array("&quot;".utf8)
    private static let apostrophe = Array("&#39;".utf8)
    private static let replacement: [UInt8] = [0xEF, 0xBF, 0xBD]

    /// Appends `bytes` to `out` as HTML text. `smart` is nil for text that keeps its straight quotes (code, attributes), or the state of the paragraph's punctuation.
    static func escape(
        _ bytes: UnsafeBufferPointer<UInt8>,
        into out: inout OutputBuffer,
        smart: inout SmartPunctuation,
        smartOn: Bool
    ) {
        let count = bytes.count
        var index = 0
        let set = smartOn ? smartSet : plainSet
        if let base = bytes.baseAddress {
            while index < count {
                // The run of bytes that are copied as they are, found 16 at a time.
                let end = unsafe index + AemiKernels.firstIndex(inSet: set, base: base + index, count: count - index)
                if end > index {
                    unsafe out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[index ..< end]))
                    // A run holds ASCII only, so its last byte is its last scalar.
                    if smartOn { smart.previous = Unicode.Scalar(unsafe bytes[end - 1]) }
                    index = end
                    if index >= count { break }
                }
                let byte = unsafe bytes[index]
                switch byte {
                    case 0x26:
                        out.append(contentsOf: ampersand)
                        if smartOn { smart.previous = "&" }
                        index += 1
                    case 0x3C:
                        out.append(contentsOf: lessThan)
                        if smartOn { smart.previous = "<" }
                        index += 1
                    case 0x3E:
                        out.append(contentsOf: greaterThan)
                        if smartOn { smart.previous = ">" }
                        index += 1
                    case 0x22:
                        if smartOn {
                            let curly: Unicode.Scalar = smart.opens ? "\u{201C}" : "\u{201D}"
                            appendCurly(curly, to: &out)
                            smart.previous = curly
                        } else {
                            out.append(contentsOf: quote)
                        }
                        index += 1
                    case 0x27:
                        if smartOn {
                            let curly: Unicode.Scalar = smart.opens ? "\u{2018}" : "\u{2019}"
                            appendCurly(curly, to: &out)
                            smart.previous = curly
                        } else {
                            out.append(contentsOf: apostrophe)
                        }
                        index += 1
                    case 0x2E:
                        // Only reached with smart punctuation on: three full stops are one ellipsis.
                        if index + 2 < count, unsafe bytes[index + 1] == 0x2E, unsafe bytes[index + 2] == 0x2E {
                            out.append(contentsOf: [0xE2, 0x80, 0xA6])
                            smart.previous = "\u{2026}"
                            index += 3
                        } else {
                            out.append(0x2E)
                            smart.previous = "."
                            index += 1
                        }
                    case 0x00 ... 0x1F, 0x7F:
                        // A control: dropped, but it is still the character before the next one.
                        if smartOn { smart.previous = Unicode.Scalar(byte) }
                        index += 1
                    default:
                        let (value, length) = unsafe decode(bytes, at: index)
                        let lead = unsafe bytes[index]
                        let isWritten = value != 0xFFFD || (length == 3 && lead == 0xEF)
                        if !isWritten {
                            out.append(contentsOf: replacement)
                        } else if isAllowed(value) {
                            unsafe out.append(
                                contentsOf: UnsafeBufferPointer(rebasing: bytes[index ..< index + length])
                            )
                        }
                        if smartOn { smart.previous = Unicode.Scalar(value) ?? "\u{FFFD}" }
                        index += length
                }
            }
        }
    }

    private static func appendCurly(_ scalar: Unicode.Scalar, to out: inout OutputBuffer) {
        let value = scalar.value
        out.append(0xE0 | UInt8(value >> 12))
        out.append(0x80 | UInt8((value >> 6) & 0x3F))
        out.append(0x80 | UInt8(value & 0x3F))
    }

    /// `bytes` escaped, with the straight quotes kept.
    static func escape(_ bytes: [UInt8], into out: inout OutputBuffer) {
        var unused = SmartPunctuation()
        bytes.withUnsafeBufferPointer { unsafe escape($0, into: &out, smart: &unused, smartOn: false) }
    }
}

extension Array where Element == UInt8 {
    /// Appends the UTF-8 of `rhs`: the writer's `out += "<p>"`.
    @_disfavoredOverload
    static func += (lhs: inout [UInt8], rhs: String) { lhs.append(contentsOf: rhs.utf8) }

    /// Appends a literal: its bytes are in the binary, so nothing is checked, counted or released (a literal prefers this to the `String` one).
    static func += (lhs: inout [UInt8], rhs: StaticString) {
        unsafe lhs.append(contentsOf: UnsafeBufferPointer(start: rhs.utf8Start, count: rhs.utf8CodeUnitCount))
    }
}
