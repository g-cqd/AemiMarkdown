import Testing

@testable import MarkdownLookKit

/// The byte-level escaper does what the `String` one did: the same output for any bytes, ill-formed ones included, and the same punctuation state afterwards.
@Suite("The HTML escaper")
struct HTMLEscaperTests {
    /// Bytes drawn from what makes trouble: the reserved characters, quotes, dots, controls, white space, every length of UTF-8 sequence, the scalars a page drops, and bytes that are not UTF-8.
    /// The UTF-8 of one scalar, written out so that the noncharacters can be named.
    private static func encoded(_ value: UInt32) -> [UInt8] {
        switch value {
            case ..<0x80: [UInt8(value)]
            case ..<0x800: [0xC0 | UInt8(value >> 6), 0x80 | UInt8(value & 0x3F)]
            case ..<0x10000: [0xE0 | UInt8(value >> 12), 0x80 | UInt8((value >> 6) & 0x3F), 0x80 | UInt8(value & 0x3F)]
            default:
                [
                    0xF0 | UInt8(value >> 18), 0x80 | UInt8((value >> 12) & 0x3F), 0x80 | UInt8((value >> 6) & 0x3F),
                    0x80 | UInt8(value & 0x3F)
                ]
        }
    }

    private static let pieces: [[UInt8]] = [
        Array("a".utf8), Array("Hello ".utf8), Array("&<>\"'".utf8), Array("...".utf8), Array("..".utf8), [0x2E],
        [0x00], [0x07], [0x0A], [0x0D], [0x09], [0x20], [0x7F],
        encoded(0xE9), Array("日本語".utf8), Array("🙂".utf8), encoded(0x80), encoded(0x9F), encoded(0xA0), encoded(0x61C),
        encoded(0x200B),
        encoded(0x200E), encoded(0x202A), encoded(0x2066), encoded(0xFEFF), encoded(0xFFFE), encoded(0xFDD0),
        encoded(0xFFFD),
        encoded(0x201C) + encoded(0x2019), [0xFF], [0xC0, 0xAF], [0xC2], [0xE2, 0x82], [0xE2], [0xED, 0xA0, 0x80],
        [0xF0, 0x9F], [0xF0, 0x9F, 0x99], [0xF4, 0x90, 0x80, 0x80], [0x80], [0xBF],
        Array("(".utf8), Array("— ".utf8)
    ]

    private static func random(_ generator: inout SystemRandomNumberGenerator) -> [UInt8] {
        var bytes: [UInt8] = []
        for _ in 0 ..< Int.random(in: 0 ... 12, using: &generator) {
            bytes += pieces[Int.random(in: 0 ..< pieces.count, using: &generator)]
        }
        return bytes
    }

    @Test(arguments: [false, true])
    func `any bytes give what the String escaper gave`(smartOn: Bool) {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 4_000 {
            let bytes = Self.random(&generator)
            let start: Unicode.Scalar? = [nil, " ", "a", "(", "\u{2014}"].randomElement() ?? nil
            var old = SmartPunctuation()
            old.previous = start
            let text = String(decoding: bytes, as: UTF8.self)
            let expected = HTMLText.escaped(smartOn ? old.apply(text) : text)
            var new = SmartPunctuation()
            new.previous = start
            var out: [UInt8] = []
            bytes.withUnsafeBufferPointer { unsafe HTMLEscaper.escape($0, into: &out, smart: &new, smartOn: smartOn) }
            #expect(String(decoding: out, as: UTF8.self) == expected, "\(bytes)")
            if smartOn { #expect(new.previous == old.previous, "\(bytes)") }
        }
    }

    @Test func `a destination is judged as before`() {
        var generator = SystemRandomNumberGenerator()
        let destinations = [
            "http://a", "HTTPS://a", "mailto:a@b", "javascript:alert(1)", " java\tscript:x", "/a/b", "#x", "?q", "a:b",
            "data:text/html,x", "vbscript:x", "ftp://x", "x", "",
            "https", "httpx://", "a b:c", "\u{0}javascript:x", "file:///etc", "mailto", "HtTp:x"
        ]
        for destination in destinations {
            #expect(
                HTMLText.isSafeDestination(bytes: Array(destination.utf8)) == HTMLText.isSafeDestination(destination),
                "\(destination)"
            )
        }
        for _ in 0 ..< 2_000 {
            let bytes = (0 ..< Int.random(in: 0 ... 20, using: &generator))
                .map { _ in Array(":/?# aAhHtTpPsSmM\t\n\r".utf8).randomElement(using: &generator) ?? 0x61 }
            #expect(
                HTMLText.isSafeDestination(bytes: bytes)
                    == HTMLText.isSafeDestination(String(decoding: bytes, as: UTF8.self)),
                "\(bytes)"
            )
        }
    }
}
