import AemiMarkdown
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// A document's head, as GitHub draws it: a table of its keys and values, or its lines as code when it is not a mapping or does not read.
@Suite("A document's head")
struct FrontMatterTests {
    private func document(_ source: String) -> MarkdownDocument {
        MarkdownParser.parse(Array(source.utf8), extensions: MarkdownLook.extensions)
    }

    private func html(_ source: String) -> String { MarkdownHTMLRenderer().body(document(source)) }

    private func rows(_ source: String) -> [NativeRow] { NativeDocument(document(source)).rows }

    @Test("a YAML head is a table of its keys and values, and the body follows")
    func yamlTable() {
        let page = html("---\ntitle: A <b> note\ntags: [swift, yaml]\nmeta: {pages: 3}\nempty: ~\n---\n# Body\n")
        #expect(
            page.contains(
                "<div class=\"table-wrap front-matter\"><table>\n<thead><tr><th>title</th><th>tags</th><th>meta</th><th>empty</th></tr></thead>"
                    + "<tbody><tr><td>A &lt;b&gt; note</td><td>swift, yaml</td><td>{&quot;pages&quot;:3}</td><td></td></tr></tbody></table></div>"
            ),
            "\(page)"
        )
        #expect(page.contains("<h1>Body</h1>"))
        #expect(!page.contains("<hr"))
        #expect(!page.contains("title: A"))
    }

    @Test("TOML and JSON heads are tables too, in their order")
    func tomlAndJSON() {
        #expect(html("+++\nb = 1\na = \"x\"\n+++\ntext\n").contains("<th>b</th><th>a</th>"))
        #expect(html("{\n  \"z\": true,\n  \"y\": [1, 2]\n}\n\ntext\n").contains("<td>true</td><td>1, 2</td>"))
    }

    @Test("a head that is not a mapping, or does not read, is shown as its lines, as code in its format")
    func codeHeads() {
        let list = html("---\n- a\n- b\n---\ntext\n")
        #expect(list.contains("<code class=\"language-yaml\">"))
        #expect(list.contains("- a\n- b"))
        let broken = html("---\nkey: [unclosed\n---\ntext\n")
        #expect(broken.contains("language-yaml"))
        #expect(!broken.contains("front-matter"))
    }

    @Test("the native view draws the same table, and copying it gives the head as written")
    func native() {
        let found = rows("---\ntitle: Note\ntags: [a, b]\n---\n# Body\n")
        guard case .table(let table) = found.first?.content else {
            Issue.record("expected a table first, got \(String(describing: found.first?.content))")
            return
        }
        #expect(table.header.map { String($0.characters) } == ["title", "tags"])
        #expect(table.rows.map { $0.map { String($0.characters) } } == [["Note", "a, b"]])
        #expect(found.first?.source == "---\ntitle: Note\ntags: [a, b]\n---\n")
        guard case .code(let code) = rows("---\n- a\n---\ntext\n").first?.content else {
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
