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
        "a head is rows of its properties: nested ones indented, lists of scalars as tags, flags, dates, links, nulls"
    )
    func rows() throws {
        let panel = try #require(panel(Self.post))
        #expect(panel.format == "YAML" && panel.title == "A <b> note" && panel.count == 10)
        typealias Row = FrontMatterPanel.Row
        // ICU's time formats differ only in the space before AM (a narrow no-break space in recent versions).
        let rows = panel.rows.map { row in
            guard case .date(let text) = row.value else { return row }
            return Row(
                key: row.key,
                value: .date(text.replacingOccurrences(of: "\u{202F}", with: " ")),
                depth: row.depth
            )
        }
        #expect(
            rows == [
                Row(key: "title", value: .text("A <b> note"), depth: 0),
                Row(key: "date", value: .date("Nov 6, 2026 at 10:30 AM"), depth: 0),
                Row(key: "day", value: .date("Nov 7, 2026"), depth: 0),
                Row(key: "author", value: .none, depth: 0),
                Row(key: "name", value: .text("G"), depth: 1),
                Row(key: "url", value: .link("https://example.com/a"), depth: 1),
                Row(key: "tags", value: .tags(["swift", "yaml"]), depth: 0),
                Row(key: "draft", value: .flag(false), depth: 0),
                Row(key: "published", value: .flag(true), depth: 0),
                Row(key: "home", value: .text("/relative"), depth: 0),
                Row(key: "empty", value: .none, depth: 0),
                Row(key: "related", value: .none, depth: 0),
                Row(key: "1", value: .none, depth: 1),
                Row(key: "title", value: .text("One"), depth: 2)
            ]
        )
    }

    @Test("as HTML the panel is closed, with its format, title and count; the settings open it; its text is escaped")
    func page() {
        let closed = html(Self.post)
        #expect(closed.contains("<details class=\"front-matter\"><summary><span class=\"fm-kind\">YAML</span>"))
        #expect(
            closed.contains(
                "<span class=\"fm-title\">A &lt;b&gt; note</span><span class=\"fm-count\">10 properties</span>"
            )
        )
        #expect(closed.contains("<span class=\"fm-tag\">swift</span><span class=\"fm-tag\">yaml</span>"))
        #expect(closed.contains("<a href=\"https://example.com/a\">https://example.com/a</a>"))
        #expect(
            closed.contains("<span class=\"fm-flag on\">\u{2713}</span>")
                && closed.contains("<span class=\"fm-flag\">\u{2014}</span>")
        )
        #expect(closed.contains("calc(1.1em + 2 * var(--indent))"))
        #expect(closed.contains("<h1>Body</h1>") && !closed.contains("<hr"))
        #expect(html(Self.post, open: true).contains("<details class=\"front-matter\" open>"))
        #expect(TagBalance.problem(in: closed) == nil)
    }

    @Test("TOML and JSON heads are panels too, in their order; one property is counted as one")
    func tomlAndJSON() {
        #expect(
            html("+++\nb = 1\na = \"x\"\n+++\ntext\n")
                .contains("<tr><th>b</th><td>1</td></tr>\n<tr><th>a</th><td>x</td></tr>")
        )
        #expect(
            html("{\n  \"z\": true\n}\n\ntext\n")
                .contains("<span class=\"fm-kind\">JSON</span><span class=\"fm-count\">1 property</span>")
        )
    }

    @Test("a head that is not a mapping, or does not read, is shown as its lines, as code in its format")
    func codeHeads() {
        let list = html("---\n- a\n- b\n---\ntext\n")
        #expect(list.contains("<code class=\"language-yaml\">") && list.contains("- a\n- b"))
        let broken = html("---\nkey: [unclosed\n---\ntext\n")
        #expect(broken.contains("language-yaml") && !broken.contains("front-matter"))
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
