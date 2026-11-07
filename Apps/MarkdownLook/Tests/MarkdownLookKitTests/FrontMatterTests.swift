import AemiMarkdown
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// A document's head as a panel of its properties, closed to one line until opened; or its lines as code when it is not a mapping or
/// does not read.
@Suite("A document's head")
struct FrontMatterTests {
    private func document(_ source: String) -> MarkdownDocument {
        MarkdownParser.parse(Array(source.utf8), extensions: MarkdownLook.extensions)
    }

    private func html(_ source: String, open: Bool = false) -> String {
        var renderer = MarkdownHTMLRenderer()
        renderer.settings.opensFrontMatter = open
        return renderer.body(document(source))
    }

    private func panel(_ source: String) -> FrontMatterPanel? {
        FrontMatterPanel(
            document(source),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "UTC")!
        )
    }

    private static let post = """
        ---
        title: A <b> note
        date: 2026-11-06T10:30:00Z
        day: 2026-11-07
        author: {name: G, url: "https://example.com/a"}
        tags: [swift, yaml]
        draft: false
        published: true
        home: /relative
        empty: ~
        related:
          - {title: One}
        ---
        # Body

        """

    @Test(
        "a head is its properties: nested mappings and lists of them as groups, lists of scalars as words, flags, dates, links"
    )
    func rows() throws {
        let panel = try #require(panel(Self.post))
        #expect(panel.title == "A <b> note" && panel.count == 10)
        typealias Row = FrontMatterPanel.Row
        // ICU's time formats differ only in the space before AM (a narrow no-break space in recent versions).
        let rows = panel.rows.map { row in
            guard case .date(let text) = row.value else { return row }
            return Row(key: row.key, value: .date(text.replacingOccurrences(of: "\u{202F}", with: " ")))
        }
        #expect(
            rows == [
                Row(key: "title", value: .text("A <b> note")),
                Row(key: "date", value: .date("Nov 6, 2026 at 10:30 AM")),
                Row(key: "day", value: .date("Nov 7, 2026")),
                Row(
                    key: "author",
                    value: .none,
                    children: [
                        Row(key: "name", value: .code("G")), Row(key: "url", value: .link("https://example.com/a"))
                    ]
                ),
                Row(key: "tags", value: .tags(["swift", "yaml"], code: true)),
                Row(key: "draft", value: .flag(false)),
                Row(key: "published", value: .flag(true)),
                Row(key: "home", value: .code("/relative")),
                Row(key: "empty", value: .none),
                Row(
                    key: "related",
                    value: .none,
                    children: [Row(key: "1", value: .none, children: [Row(key: "title", value: .text("One"))])]
                )
            ]
        )
    }

    @Test(
        "words a program reads are code (no white space, not a prose property); prose, and lists with prose in them, are not"
    )
    func codeWords() throws {
        let panel = try #require(
            panel(
                "---\ntitle: Notes\nmodel: anthropic/claude-opus\neffort: high\nsummary: short\n"
                    + "note: two words\nmodels: [Claude Opus 4.6, gpt-5]\ntools: [read, apple-docs/*]\nn: 3\n---\n"
            )
        )
        #expect(
            panel.rows.map(\.value) == [
                .text("Notes"), .code("anthropic/claude-opus"), .code("high"), .text("short"), .text("two words"),
                .tags(["Claude Opus 4.6", "gpt-5"], code: false), .tags(["read", "apple-docs/*"], code: true),
                .code("3")
            ]
        )
    }

    @Test("a prose value is the Markdown it is written in, in both views; raw HTML in it is text")
    func proseMarkdown() {
        let source = "---\ndescription: |\n  Use **PROACTIVELY**, see `ask`.\n\n  - one\n  - <b>two</b>\n---\n"
        let page = html(source)
        #expect(
            page.contains(
                "<div class=\"fm-value fm-prose\"><p>Use <strong>PROACTIVELY</strong>, see <code data-n>ask</code>.</p>"
            )
        )
        #expect(
            page.contains("<li><p>one</p></li>") && page.contains("&lt;b&gt;two&lt;/b&gt;") && !page.contains("<b>two")
        )
        #expect(TagBalance.problem(in: page) == nil)
        let rows = NativeDocument(FrontMatterPanel.prose("Use **this**.\n\n- one\n- two\n")).rows
        #expect(rows.count == 3)
        guard case .text(let first) = rows.first?.content else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(String(first.string.characters) == "Use this.")
    }

    @Test("a head nested past the deepest group is written as its JSON")
    func deep() throws {
        let depth = FrontMatterPanel.deepest + 2
        let nested = String(repeating: "{a: ", count: depth) + "1" + String(repeating: "}", count: depth)
        var row = try #require(panel("---\nk: \(nested)\n---\n"))
        var level = 0
        while let first = row.rows.first, first.isGroup {
            row.rows = first.children
            level += 1
        }
        #expect(level == FrontMatterPanel.deepest)
        guard case .code(let text) = row.rows.first?.value else {
            Issue.record("expected JSON text")
            return
        }
        #expect(text.hasPrefix("{\"a\":"))
    }

    @Test(
        "as HTML the panel is closed, with its title and count and no format; the settings open it; its text is escaped"
    )
    func page() {
        let closed = html(Self.post)
        #expect(
            closed.contains(
                "<details class=\"front-matter\"><summary><span class=\"fm-title\">A &lt;b&gt; note</span>"
                    + "<span class=\"fm-count\">10 properties</span></summary>"
            )
        )
        #expect(!closed.contains("YAML") && !closed.contains("<table"))
        // A key over its value; words of a list as words; flags as written; a group as a disclosure of its own column.
        #expect(
            closed.contains(
                "<div class=\"fm-row\"><span class=\"fm-key\">draft</span><div class=\"fm-value\"><code>false</code></div></div>"
            )
        )
        #expect(
            closed.contains(
                "<span class=\"fm-tags\"><span><code>swift</code></span><span><code>yaml</code></span></span>"
            )
        )
        #expect(closed.contains("<a href=\"https://example.com/a\">https://example.com/a</a>"))
        #expect(
            closed.contains(
                "<details class=\"fm-group\" open><summary><span class=\"fm-key\">related</span></summary><div class=\"fm\">"
                    + "<details class=\"fm-group\" open><summary><span class=\"fm-key\">1</span></summary>"
            )
        )
        #expect(closed.contains("<h1>Body</h1>") && !closed.contains("<hr"))
        #expect(html(Self.post, open: true).contains("<details class=\"front-matter\" open>"))
        #expect(TagBalance.problem(in: closed) == nil)
    }

    @Test("TOML and JSON heads are panels too, in their order; one property is counted as one")
    func tomlAndJSON() {
        #expect(
            html("+++\nb = 1\na = \"x\"\n+++\ntext\n")
                .contains(
                    "<span class=\"fm-key\">b</span><div class=\"fm-value\"><code>1</code></div></div>\n"
                        + "<div class=\"fm-row\"><span class=\"fm-key\">a</span><div class=\"fm-value\"><code>x</code></div>"
                )
        )
        #expect(
            html("{\n  \"z\": true\n}\n\ntext\n")
                .contains("<summary><span class=\"fm-count\">1 property</span></summary>")
        )
    }

    @Test("a head that is not a mapping, or does not read, is shown as its lines, as code in its format")
    func codeHeads() {
        let list = html("---\n- a\n- b\n---\ntext\n")
        #expect(list.contains("<code class=\"language-yaml\">") && list.contains("- a\n- b"))
        let broken = html("---\nkey: [unclosed\n---\ntext\n")
        #expect(broken.contains("language-yaml") && !broken.contains("front-matter"))
    }

    @Test("a block scalar's last newline is not drawn as a line; its inner lines are kept")
    func blockScalars() throws {
        let panel = try #require(panel("---\nfolded: >\n  one\n  two\nliteral: |\n  a\n  b\n---\n"))
        #expect(panel.rows.map(\.value) == [.text("one two"), .text("a\nb")])
    }

    @Test("dates as Jekyll and YAML 1.1 write them: a space before the offset, which may lack its colon or its minutes")
    func spacedDates() {
        let dates = DateText(locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!)
        func read(_ text: String) -> String? { dates.readable(text)?.replacingOccurrences(of: "\u{202F}", with: " ") }
        #expect(read("2026-03-14 09:30:00 +0100") == "Mar 14, 2026 at 8:30 AM")
        #expect(read("2026-03-14 09:30:00 +01:00") == "Mar 14, 2026 at 8:30 AM")
        #expect(read("2001-12-14 21:59:43.10 -5") == "Dec 15, 2001 at 2:59 AM")
        #expect(read("2026-03-14 09:30 +0100") == nil)
        #expect(read("2026-03-14 +0100") == nil && read("2026-03-14 09:30:00 +01000") == nil)
    }

    @Test("the native view gets the same panel, and copying it gives the head as written")
    func native() {
        let found = NativeDocument(document("---\ntitle: Note\ntags: [a, b]\n---\n# Body\n")).rows
        guard case .frontMatter(let panel) = found.first?.content else {
            Issue.record("expected the panel first, got \(String(describing: found.first?.content))")
            return
        }
        #expect(panel.rows.map(\.key) == ["title", "tags"] && panel.title == "Note")
        #expect(found.first?.source == "---\ntitle: Note\ntags: [a, b]\n---\n")
        guard case .code(let code) = NativeDocument(document("---\n- a\n---\ntext\n")).rows.first?.content else {
            Issue.record("a list head is code")
            return
        }
        #expect(code.language == "yaml" && code.raw == "- a")
    }

    @Test("a document without a head reads as before")
    func noHead() {
        let source = "# Title\n\n---\n\ntext\n"
        #expect(html(source) == MarkdownHTMLRenderer().body(MarkdownParser.parse(Array(source.utf8))))
    }
}
