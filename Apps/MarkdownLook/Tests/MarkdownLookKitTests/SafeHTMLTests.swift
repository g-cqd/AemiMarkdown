import AemiMarkdown
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// Safe HTML tags interpreted by both the HTML renderer and the native SwiftUI document model:
/// `<br>` (inline & inside tables) and `<details>` / `<summary>` (collapsible disclosures).
@Suite("Safe HTML tags (<br>, <details>, <summary>)")
struct SafeHTMLTests {
    private func html(_ source: String) -> String {
        MarkdownHTMLRenderer().body(MarkdownParser.parse(Array(source.utf8)))
    }

    private func rows(_ source: String) -> [NativeRow] {
        NativeDocument(MarkdownParser.parse(Array(source.utf8))).rows
    }

    private func balanced(_ markup: String, sourceLine: Int = #line) {
        #expect(
            TagBalance.problem(in: markup) == nil,
            "\(TagBalance.problem(in: markup) ?? "") in \(markup.prefix(400))",
            sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: sourceLine, column: 1)
        )
    }

    // MARK: <br>

    @Test(arguments: ["<br>", "<br/>", "<br />", "<BR>", "<Br  />"])
    func `inline br tags become line breaks in table cells and prose`(tag: String) {
        let md = "| A | B |\n| --- | --- |\n| one\(tag)two | three |\n\nalpha\(tag) beta"
        let out = html(md)
        #expect(out.contains("one<br>\ntwo"))
        #expect(!out.contains("&lt;br"))
        #expect(out.contains("alpha<br>\n beta"))
        balanced(out)

        let nativeRows = rows(md)
        guard case .table(let table) = nativeRows[0].content else {
            Issue.record("expected table row")
            return
        }
        #expect(String(table.rows[0][0].characters) == "one\ntwo")
        guard case .text(let para) = nativeRows[1].content else {
            Issue.record("expected paragraph row")
            return
        }
        // Leading space after `<br>` is collapsed in native text just as HTML collapses it on a new line.
        #expect(String(para.string.characters) == "alpha\nbeta")
    }

    @Test func `br with attributes or inside code spans is never interpreted as a break`() {
        let md = "| A | B |\n| --- | --- |\n| `<br>` | x<br onclick=\"alert(1)\">y |"
        let out = html(md)
        #expect(out.contains("<code data-n>&lt;br&gt;</code>"))
        #expect(out.contains("&lt;br onclick=&quot;alert(1)&quot;&gt;"))
        #expect(!out.contains("onclick=\""))
        balanced(out)

        guard case .table(let table) = rows(md)[0].content else {
            Issue.record("expected table row")
            return
        }
        #expect(String(table.rows[0][0].characters) == "<br>")
        #expect(String(table.rows[0][1].characters) == "x<br onclick=\"alert(1)\">y")
    }

    @Test func `table column measurement uses longest line across br breaks`() {
        let md = "| Col | Other |\n| --- | --- |\n| short<br>line<br>here<br>too | x |"
        guard case .table(let table) = rows(md)[0].content else {
            Issue.record("expected table row")
            return
        }
        let measured = NativeTableShape.measure(table.rows[0][0])
        #expect(measured.length == 5)  // "short" (5 chars), not 20
        #expect(measured.word == 5)
        let htmlMeasured = TableLayout.measure(bytes: Array("short<br>\nline<br>\nhere<br>\ntoo".utf8), from: 0)
        #expect(htmlMeasured.length == 5)
        #expect(htmlMeasured.word == 5)
    }

    // MARK: <details> and <summary>

    @Test func `details and summary with blank-line separated Markdown body`() {
        let md = """
            <details>
            <summary>Click `me` and **now**</summary>

            Body paragraph.

            - item 1
            - item 2

            </details>
            """
        let out = html(md)
        #expect(
            out.contains(
                "<details class=\"disclosure\"><summary><span class=\"disclosure-label\">Click <code data-n>me</code> and <strong>now</strong></span></summary>"
            )
        )
        #expect(out.contains("<div class=\"disclosure-body\">"))
        #expect(out.contains("<p>Body paragraph.</p>"))
        #expect(out.contains("<li><p>item 1</p></li>"))
        #expect(out.contains("</details>"))
        balanced(out)

        let nativeRows = rows(md)
        #expect(nativeRows.count == 1)
        guard case .details(let details) = nativeRows[0].content else {
            Issue.record("expected details row, got \(nativeRows)")
            return
        }
        #expect(!details.isOpen)
        #expect(String(details.summary.characters) == "Click me and now")
        #expect(details.rows.count == 3)  // paragraph + 2 list items
        #expect(nativeRows[0].source.contains("<details>"))
        #expect(nativeRows[0].source.contains("</details>"))
    }

    @Test func `details open attribute and immediate body without blank lines`() {
        let md = """
            <details open>
            <summary>Always open</summary>
            Immediate **bold** line.
            </details>
            """
        let out = html(md)
        #expect(out.contains("<details class=\"disclosure\" open>"))
        #expect(out.contains("Always open"))
        #expect(out.contains("<strong>bold</strong>"))
        balanced(out)

        guard case .details(let details) = rows(md)[0].content else {
            Issue.record("expected details row")
            return
        }
        #expect(details.isOpen)
        #expect(String(details.summary.characters) == "Always open")
        #expect(details.rows.count == 1)
        if case .text(let t) = details.rows[0].content {
            #expect(String(t.string.characters) == "Immediate bold line.")
        } else {
            Issue.record("expected body text row")
        }
    }

    @Test func `split summary across blank lines and inline code tags inside summary`() {
        let md = """
            <details>

            <summary>

            Terraform <code>cloudflare_ruleset</code> resource

            </summary>

            Details body.

            </details>
            """
        let out = html(md)
        #expect(out.contains("<details class=\"disclosure\"><summary><span class=\"disclosure-label\">Terraform"))
        #expect(out.contains("Details body."))
        balanced(out)

        guard case .details(let details) = rows(md)[0].content else {
            Issue.record("expected details row")
            return
        }
        #expect(String(details.summary.characters).contains("Terraform"))
        #expect(details.rows.count == 1)
    }

    @Test func `same-line details and summary and default summary when omitted`() {
        let md1 = "<details><summary>Inline</summary>\n\nBody\n\n</details>"
        balanced(html(md1))
        guard case .details(let d1) = rows(md1)[0].content else {
            Issue.record("expected details row")
            return
        }
        #expect(String(d1.summary.characters) == "Inline" && d1.rows.count == 1)

        let md2 = "<details>\n\nNo summary here.\n\n</details>"
        let out2 = html(md2)
        #expect(out2.contains("<summary><span class=\"disclosure-label\">Details</span></summary>"))
        balanced(out2)
        guard case .details(let d2) = rows(md2)[0].content else {
            Issue.record("expected details row")
            return
        }
        #expect(d2.summary.characters.isEmpty && d2.rows.count == 1)
    }

    @Test func `nested details and details inside quotes and lists`() {
        let nested = """
            <details open>
            <summary>Outer</summary>

            <details>
            <summary>Inner</summary>

            Deep paragraph.

            </details>

            </details>
            """
        let out = html(nested)
        #expect(out.components(separatedBy: "<details class=\"disclosure\"").count == 3)
        balanced(out)

        guard case .details(let outer) = rows(nested)[0].content else {
            Issue.record("expected outer details")
            return
        }
        #expect(outer.isOpen && outer.rows.count == 1)
        guard case .details(let inner) = outer.rows[0].content else {
            Issue.record("expected inner details")
            return
        }
        #expect(!inner.isOpen && String(inner.summary.characters) == "Inner" && inner.rows.count == 1)

        let inQuote = "> <details>\n> <summary>Quoted</summary>\n>\n> Inside quote.\n>\n> </details>"
        balanced(html(inQuote))
        let quoteRows = rows(inQuote)
        #expect(quoteRows.count == 1)
        #expect(quoteRows[0].guides == [.bar(nil, continues: false)])
        if case .details(let qd) = quoteRows[0].content {
            #expect(String(qd.summary.characters) == "Quoted" && qd.rows.count == 1 && qd.rows[0].guides.isEmpty)
        } else {
            Issue.record("expected quoted details")
        }
    }

    @Test func `hostile attributes, unclosed details, stray closings, and excessive nesting stay safe and balanced`() {
        let hostile = """
            <details open onclick="alert(1)" onmouseover="evil()">
            <summary onclick="x()"><script>alert(1)</script>Title</summary>

            <script>bad()</script>

            </details>
            """
        let out = html(hostile)
        #expect(!out.contains("onclick"))
        #expect(!out.contains("onmouseover"))
        #expect(!out.contains("<script"))
        #expect(out.contains("&lt;script&gt;"))
        balanced(out)

        // Unclosed <details> closes cleanly at EOF.
        let unclosed = "<details>\n<summary>Unclosed</summary>\n\nStill visible."
        let unclosedOut = html(unclosed)
        #expect(unclosedOut.contains("</details>"))
        balanced(unclosedOut)
        if case .details(let ud) = rows(unclosed)[0].content {
            #expect(String(ud.summary.characters) == "Unclosed" && ud.rows.count == 1)
        } else {
            Issue.record("expected unclosed details to flush cleanly")
        }

        // Stray </details> stays literal HTML source and keeps HTML balanced.
        let stray = "</details>\n\nnormal paragraph"
        let strayOut = html(stray)
        #expect(strayOut.contains("&lt;/details&gt;"))
        balanced(strayOut)

        // Deep nesting beyond maxDetailsDepth never traps or produces unbalanced HTML.
        let deep =
            String(repeating: "<details>\n<summary>d</summary>\n\n", count: 40)
            + "leaf\n\n"
            + String(repeating: "</details>\n\n", count: 40)
        let deepOut = html(deep)
        balanced(deepOut)
        let deepRows = rows(deep)
        #expect(!deepRows.isEmpty)
    }

    @Test func `table inside details with br tags renders cleanly in both HTML and native`() {
        let md = """
            <details open>
            <summary>Matrix</summary>

            | Name | Notes |
            | --- | --- |
            | foo | line 1<br>line 2 |

            </details>
            """
        let out = html(md)
        #expect(out.contains("line 1<br>\nline 2"))
        balanced(out)

        guard case .details(let d) = rows(md)[0].content,
            let firstRow = d.rows.first,
            case .table(let t) = firstRow.content
        else {
            Issue.record("expected table inside details")
            return
        }
        #expect(String(t.rows[0][1].characters) == "line 1\nline 2")
    }
}
