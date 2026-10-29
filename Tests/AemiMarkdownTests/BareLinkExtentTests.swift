import Testing

@testable import AemiMarkdown

/// A `www.` or scheme link runs to a space or `<` in the source as written (GFM 6.9), through an escape, an entity or a stray backtick that ended its
/// text node (found by the differential test). Expected HTML is cmark-gfm 0.29.0.gfm.13's.
@Suite("A bare link runs through escapes and entities, as written")
struct BareLinkExtentTests {
    @Test(arguments: [
        ("http://example.com/a\\*b", "<p><a href=\"http://example.com/a%5C*b\">http://example.com/a\\*b</a></p>\n"),
        ("www.example.com)\\*word", "<p><a href=\"http://www.example.com)%5C*word\">www.example.com)\\*word</a></p>\n"),
        (
            "see http://example.com/a_b\\*<http://a.b>",
            "<p>see <a href=\"http://example.com/a_b%5C\">http://example.com/a_b\\</a>*<a href=\"http://a.b\">http://a.b</a></p>\n"
        ),
        (
            "http://example.com/x&#35;",
            "<p><a href=\"http://example.com/x&amp;#35\">http://example.com/x&amp;#35</a>;</p>\n"
        ),
        (
            "www.example.com&amp;x y",
            "<p><a href=\"http://www.example.com&amp;amp;x\">www.example.com&amp;amp;x</a> y</p>\n"
        ),
        ("www.example.com\\\\", "<p><a href=\"http://www.example.com%5C%5C\">www.example.com\\\\</a></p>\n"),
        ("http://example.com/`x", "<p><a href=\"http://example.com/%60x\">http://example.com/`x</a></p>\n"),
        ("http://a.b/c *d*", "<p><a href=\"http://a.b/c\">http://a.b/c</a> <em>d</em></p>\n")
    ])
    func `renders as cmark-gfm does`(markdown: String, html: String) {
        #expect(SpecHTMLRenderer.html(of: MarkdownParser.parse(Array(markdown.utf8), extensions: .gfm)) == html)
    }

    @Test func `the document stays valid when a link takes part of an entity`() {
        let document = MarkdownParser.parse(Array("a http://example.com/x&#35; b\n".utf8), extensions: .gfm)
        #expect(TapeValidator.problem(in: document) == nil)
    }
}
