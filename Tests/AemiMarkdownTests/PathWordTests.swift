import Testing

@testable import AemiMarkdown

/// `MarkdownExtensions.pathWords` (ADR-0012): in a word that names a path, `*`, `_` and `~` are the path's; elsewhere, and with the
/// extension off, emphasis reads as CommonMark says.
@Suite("Path words keep their underscores and stars")
struct PathWordTests {
    private static let on: MarkdownExtensions = [.github, .pathWords]

    private static func html(_ markdown: String, _ extensions: MarkdownExtensions = on) -> String {
        SpecHTMLRenderer.html(of: MarkdownParser.parse(Array(markdown.utf8), extensions: extensions))
    }

    @Test func `a path's underscores and stars stay, whatever opens the word`() {
        let path = "/var/folders/_l/mtv6_00gn/T/tmpsgvyf0q_/project/notes.txt"
        #expect(Self.html("See \(path):12 now.") == "<p>See \(path):12 now.</p>\n")
        #expect(Self.html("Logs in ~/a_b/*.log and /var/*.png.") == "<p>Logs in ~/a_b/*.log and /var/*.png.</p>\n")
        #expect(Self.html("(\(path)) and \"/x/_y_\"") == "<p>(\(path)) and &quot;/x/_y_&quot;</p>\n")
        #expect(Self.html("in ~/old~/new~") == "<p>in ~/old~/new~</p>\n", "no strikethrough inside a home path")
    }

    @Test func `emphasis around and beside a path still reads, and other words are CommonMark's`() {
        #expect(Self.html("*/usr/local* and _/opt/x_") == "<p><em>/usr/local</em> and <em>/opt/x</em></p>\n")
        #expect(Self.html("**bold** /a_b/ _it_") == "<p><strong>bold</strong> /a_b/ <em>it</em></p>\n")
        #expect(Self.html("a/_b_/c") == "<p>a/<em>b</em>/c</p>\n", "a relative path is prose, as CommonMark reads it")
        #expect(Self.html("`/a/_b_/` stays code") == "<p><code>/a/_b_/</code> stays code</p>\n")
    }

    @Test func `off, a path reads as CommonMark reads it`() {
        #expect(Self.html("/x/_a/b_/c", .github) == "<p>/x/<em>a/b</em>/c</p>\n")
        #expect(Self.html("/x/_a/b_/c") == "<p>/x/_a/b_/c</p>\n")
    }

    @Test func `a word is read once, however many delimiters it holds`() {
        let long = "/" + String(repeating: "a_", count: 50_000)
        var html = ""
        // Read once, 2 ms here; read again for each of its 50,000 underscores, 2 s (diary 2026-11-22-02).
        let took = ContinuousClock().measure { html = Self.html(long + " _done_") }
        #expect(html.hasSuffix("<em>done</em></p>\n"))
        #expect(took < .seconds(2), "\(took)")
    }
}
