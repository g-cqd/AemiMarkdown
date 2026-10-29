import Testing

@testable import AemiMarkdown

/// A task list marker needs a space or a tab after it on its own line (cmark-gfm 0.29.0.gfm.13, found by the differential test). Expected HTML is
/// cmark-gfm's.
@Suite("A task list marker needs white space after it")
struct TaskMarkerTests {
    @Test(arguments: [
        ("- [x]\n", "<ul>\n<li>[x]</li>\n</ul>\n"),
        ("- [x] \n", "<ul>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> </li>\n</ul>\n"),
        ("- [x]\t\n", "<ul>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> </li>\n</ul>\n"),
        ("- [ ]   \n", "<ul>\n<li><input type=\"checkbox\" disabled=\"\" /> </li>\n</ul>\n"),
        ("- [x]\n  foo\n", "<ul>\n<li>[x]\nfoo</li>\n</ul>\n"),
        ("+    [x]\n", "<ul>\n<li>[x]</li>\n</ul>\n"),
        ("- [x] a\n", "<ul>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> a</li>\n</ul>\n")
    ])
    func `renders as cmark-gfm does`(markdown: String, html: String) {
        #expect(SpecHTMLRenderer.html(of: MarkdownParser.parse(Array(markdown.utf8), extensions: .gfm)) == html)
    }

    @Test func `a marker at the end of a streamed piece waits for what follows it`() {
        var parser = MarkdownParser(extensions: .gfm)
        parser.append(Array("- [x]".utf8))
        let before = SpecHTMLRenderer.html(of: parser.snapshot())
        parser.append(Array(" done\n".utf8))
        parser.finish()
        #expect(before == "<ul>\n<li>[x]</li>\n</ul>\n")
        #expect(SpecHTMLRenderer.html(of: parser.snapshot()).contains("checkbox"))
    }
}
