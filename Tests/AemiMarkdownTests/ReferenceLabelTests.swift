import Testing

@testable import AemiMarkdown

/// A label is matched by its normalized form: no outer white space, runs of white space as one space, Unicode case folded. The folding is skipped for text
/// that has no case (ask roadmap 0205, E-labels); the three passes over a `String` that it replaced are the oracle.
@Suite("Reference labels are normalized as the three passes over a String normalized them")
struct ReferenceLabelTests {
    private func reference(_ label: String) -> [UInt8] {
        let joined = label.split(whereSeparator: { " \t\n\r".contains($0) }).joined(separator: " ")
        return Array(joined.lowercased().uppercased().lowercased().utf8)
    }

    private func normalized(_ label: String) -> [UInt8] {
        var out: [UInt8] = []
        ReferenceTable.normalize(Array(label.utf8), into: &out)
        return out
    }

    @Test(arguments: [
        "Foo Bar", "  Foo \t Bar \n", "ẞ", "ß", "STRASSE", "ǅ", "Ä Ö", "ä   ö", "日本語", "  日本  語 ", "العربية",
        "🙂 Emoji 🙂", "Ωmega", "ΑΣ", "İstanbul", "ı", "ﬁ", "ǆ",
        "한국어", "हिन्दी", "ÅÅ", "e\u{301}", "Σίσυφος"
    ])
    func `labels of every script`(label: String) {
        #expect(normalized(label) == reference(label), "\(label.debugDescription)")
    }

    @Test func `text that is not valid UTF-8 is replaced as it always was`() {
        var out: [UInt8] = []
        ReferenceTable.normalize([0x61, 0xFF, 0x42, 0xC3], into: &out)
        #expect(out == Array("a\u{FFFD}b\u{FFFD}".utf8))
    }
}
