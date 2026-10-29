import Testing

@testable import AemiMarkdown

/// A lazy continuation line keeps its leading whitespace, as in cmark 0.31.2 (found by the differential test, 12 of 16 differences on 5,000
/// random inputs): plain text drops it after a soft or trailing-space break, a code span and a backslash break keep it. Expected HTML is cmark's.
@Suite("Lazy continuation lines keep their leading whitespace where cmark keeps it")
struct LazyContinuationTests {
    @Test(arguments: [
        ("- `a\n b`\n", "<ul>\n<li><code>a  b</code></li>\n</ul>\n"),
        ("> `a\n  b`\n", "<blockquote>\n<p><code>a   b</code></p>\n</blockquote>\n"),
        ("> `a\n>  b`\n", "<blockquote>\n<p><code>a b</code></p>\n</blockquote>\n"),
        ("`a\n  b`\n", "<p><code>a b</code></p>\n"),
        ("- `\n `\n", "<ul>\n<li><code>  </code></li>\n</ul>\n"),
        ("- a\\\n b\n", "<ul>\n<li>a<br />\n b</li>\n</ul>\n"),
        ("- a  \n b\n", "<ul>\n<li>a<br />\nb</li>\n</ul>\n"),
        ("- a\n   b\n", "<ul>\n<li>a\nb</li>\n</ul>\n"),
        ("> a\n  b\n", "<blockquote>\n<p>a\nb</p>\n</blockquote>\n")
    ])
    func `renders as cmark does`(markdown: String, html: String) {
        #expect(SpecHTMLRenderer.html(of: MarkdownParser.parse(Array(markdown.utf8), extensions: [])) == html)
    }

    @Test func `a lazy line streamed in pieces renders as the whole parse`() {
        let bytes = Array("> `a\n  b` and\n  more text\n".utf8)
        var parser = MarkdownParser(extensions: [])
        for byte in bytes { parser.append([byte]) }
        parser.finish()
        #expect(
            SpecHTMLRenderer.html(of: parser.snapshot())
                == SpecHTMLRenderer.html(of: MarkdownParser.parse(bytes, extensions: [])))
    }
}
