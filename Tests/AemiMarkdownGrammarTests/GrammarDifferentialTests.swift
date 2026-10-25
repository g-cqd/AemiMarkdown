import AemiRegex
import Testing

@testable import AemiMarkdown

/// The spec defines autolinks and raw HTML tags by regular grammars. The parser reads them with hand-written byte scanners, because a scan of an 80-byte line is cheaper than a
/// regular-expression search; these tests run the spec's own grammar, as AemiRegex compiles it, over generated and mutated inputs and require the same answer
/// (ADR-0001, decision 7). They build only with `AEMIMARKDOWN_DEV=1`, because AemiRegex has no remote to depend on yet.
@Suite("The hand-written scanners agree with the spec's grammars")
struct GrammarDifferentialTests {
    // CommonMark 0.31.2, 6.4 and 6.6: an absolute URI, an email address, an open tag, a closing tag.
    static let uri = #"^<[A-Za-z][A-Za-z0-9+.\-]{1,31}:[^\x00-\x20<>\x7f]*>"#
    static let email =
        #"^<[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~\-]+@[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*>"#
    static let openTag =
        #"^<[A-Za-z][A-Za-z0-9\-]*(?:[ \t\n\x0c\r]+[A-Za-z_:][A-Za-z0-9_.:\-]*(?:[ \t\n\x0c\r]*=[ \t\n\x0c\r]*(?:[^ \t\n\x0c\r"'=<>`]+|'[^']*'|"[^"]*"))?)*[ \t\n\x0c\r]*/?>"#
    static let closingTag = #"^</[A-Za-z][A-Za-z0-9\-]*[ \t\n\x0c\r]*>"#

    /// Pieces that form and break the grammars, so random concatenations land on both sides of every rule.
    static let pieces: [String] = [
        "<", "</", ">", "/>", "1", "9z", "abcdefghijklmnopqrstuvwxyzabcdef", "abcdefghijklmnopqrstuvwxyzabcdefg", "/p>",
        "/em >", "/b\n>", "div>", "a href=\"u\">", "br/>", "a", "b1", "-", "_", ":", ".",
        "@", "=", "\"", "'", "`", " ", "\n", "\t", "x-y", "href",
        "src=\"u\"", "mailto", "http", "://",
        "co.uk", "é", "\u{7f}", "\u{1}", "!", "#", "?", "{", "|", "~", "&", "*", "+"
    ]

    static func input(seed: UInt64) -> [UInt8] {
        var generator = SeededGenerator(state: seed)
        var bytes: [UInt8] = []
        for _ in 0 ..< Int.random(in: 2 ... 14, using: &generator) {
            bytes += Array(pieces.randomElement(using: &generator)!.utf8)
        }
        return bytes
    }

    private func regexEnd(_ pattern: Pattern, _ bytes: [UInt8]) -> Int? {
        pattern.firstMatch(in: bytes)?.range.upperBound
    }

    @Test(arguments: [(uri, 0), (email, 1)])
    func `autolinks are found as the grammar finds them`(grammar: String, kind: Int) throws {
        let pattern = try Pattern(grammar)
        var agreed = 0
        for seed in 0 ..< 6_000 {
            let bytes = [UInt8(ascii: "<")] + Self.input(seed: UInt64(seed))
            let text = ContiguousArray(bytes)
            let expected = regexEnd(pattern, bytes)
            let found = InlineParser.autolink(text, at: 0)
            // `autolink` tries a URI first and an address second, so a URI is what it reports when both fit; the grammars do not overlap on `:`.
            if let found, found.1 == kind {
                #expect(found.0 == expected, "seed \(seed): \(String(decoding: bytes, as: UTF8.self).debugDescription)")
                agreed += 1
            } else if expected != nil, found == nil || found?.1 != kind {
                // the other grammar claimed it first: both match the same bytes only if the other is a URI
                #expect(
                    kind == 1 && found?.1 == 0,
                    "seed \(seed): grammar matched, scanner did not: \(String(decoding: bytes, as: UTF8.self).debugDescription)"
                )
            }
        }
        #expect(agreed > 0, "the generator never produced a match for this grammar")
    }

    @Test(arguments: [openTag, closingTag])
    func `tags end where the grammar says`(grammar: String) throws {
        let pattern = try Pattern(grammar)
        var agreed = 0
        for seed in 0 ..< 8_000 {
            let bytes = [UInt8(ascii: "<")] + Self.input(seed: UInt64(seed))
            let expected = regexEnd(pattern, bytes)
            let found = HTMLTagScanner.tag(ContiguousArray(bytes), 0, bytes.count)
            let isClosing = grammar == Self.closingTag
            let wantsClosing = bytes.count > 1 && bytes[1] == UInt8(ascii: "/")
            guard isClosing == wantsClosing else { continue }
            #expect(found == expected, "seed \(seed): \(String(decoding: bytes, as: UTF8.self).debugDescription)")
            if expected != nil { agreed += 1 }
        }
        #expect(agreed > 0, "the generator never produced a match for this grammar")
    }
}

/// SplitMix64, so a failure names a seed that reproduces it.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
