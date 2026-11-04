import AemiMarkdown
import CoreGraphics
import Foundation
import Testing

@testable import MarkdownLookKit

/// The HTML a document becomes (ADR 0007): the structure a reader sees, and nothing in it the document could use to act.
@Suite("A document as HTML")
struct MarkdownHTMLTests {
    private func html(_ source: String, smart: Bool = true) -> String {
        var renderer = MarkdownHTMLRenderer()
        renderer.smartPunctuation = smart
        return renderer.body(MarkdownParser.parse(Array(source.utf8)))
    }

    private func balanced(_ markup: String, sourceLine: Int = #line) {
        #expect(
            TagBalance.problem(in: markup) == nil,
            "\(TagBalance.problem(in: markup) ?? "") in \(markup.prefix(300))",
            sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: sourceLine, column: 1)
        )
    }

    @Test func `headings, paragraphs and emphasis`() {
        let out = html("# One\n\n###### Six\n\nA *b* **c** ~~d~~ `e`")
        #expect(out.contains("<h1>One</h1>") && out.contains("<h6>Six</h6>"))
        #expect(out.contains("<p>A <em>b</em> <strong>c</strong> <del>d</del> <code>e</code></p>"))
        balanced(out)
    }

    @Test func `lists are tight or loose, ordered lists keep their start, and tasks have checkboxes`() {
        #expect(html("- a\n- b").contains("<ul class=\"tight\"><li>a"))
        let loose = html("- a\n\n- b")
        #expect(loose.contains("<ul><li><p>a</p>") && !loose.contains("tight"))
        #expect(html("3. x\n4. y").contains(" start=\"3\""))
        #expect(!html("1. x").contains("start"))
        let tasks = html("- [x] done\n- [ ] todo")
        #expect(
            tasks.contains("<input type=\"checkbox\" disabled checked>")
                && tasks.contains("<input type=\"checkbox\" disabled> todo")
        )
        balanced(loose)
        balanced(tasks)
        balanced(html("1. a\n   - b\n     1. c\n2. d"))
    }

    @Test func `tables keep their alignment and their header`() {
        let out = html("| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |")
        #expect(
            out.contains("<thead>") && out.contains("<th class=\"c\">b</th>") && out.contains("<td class=\"r\">3</td>")
                && out.contains("<tbody>")
        )
        balanced(out)
    }

    @Test func `alerts, quotes and footnotes`() {
        let alert = html("> [!WARNING]\n> careful")
        #expect(alert.contains("class=\"alert warning\"") && alert.contains(">Warning<") && alert.contains("careful"))
        #expect(html("> plain").contains("<blockquote>"))
        let note = html("a[^1]\n\n[^1]: text")
        #expect(note.contains("<sup class=\"fn\">1</sup>") && note.contains("class=\"footnote\""))
        balanced(alert)
        balanced(note)
    }

    @Test func `code is escaped, tagged with its language, and keeps its quotes straight`() {
        let out = html("```swift\nlet a = \"x\" < 2 && true\n```")
        #expect(
            out.contains(
                "<pre><code class=\"language-swift\">let a = &quot;x&quot; &lt; 2 &amp;&amp; true\n</code></pre>"
            )
        )
        let span = html("say `\"hi\" it's...`")
        #expect(
            span.contains("<code>\"hi\" it's...</code>".replacing("\"", with: "&quot;").replacing("'", with: "&#39;"))
        )
    }

    @Test func `smart punctuation touches prose and not code`() {
        #expect(html("He said \"hi\" and it's fine...").contains("He said “hi” and it’s fine…"))
        #expect(html("He said \"hi\"", smart: false).contains("&quot;hi&quot;"))
        #expect(html("(\"a\") 'b'").contains("(“a”) ‘b’"))
    }

    @Test func `raw HTML is shown and never run`() {
        let out = html("<script>alert(1)</script>\n\nA <b onclick=\"x()\">b</b> and <img src=x onerror=y>")
        #expect(!out.contains("<script") && !out.contains("<b ") && !out.contains("<img"))
        #expect(out.contains("&lt;script&gt;") && out.contains("&lt;b onclick=&quot;x()&quot;&gt;"))
        balanced(out)
    }

    @Test(arguments: [
        "[x](javascript:alert(1))", "[x](JaVaScRiPt:alert(1))", "[x](java\tscript:alert(1))", "[x](data:text/html,<b>)",
        "[x](vbscript:y)", "[x](file:///etc/passwd)",
        "[x]( javascript:alert(1))", "[x][r]\n\n[r]: javascript:alert(1)", "<javascript:alert(1)>"
    ])
    func `a link with a scheme that runs or reads is not a link`(source: String) {
        let out = html(source)
        #expect(
            !out.contains("href=\"java") && !out.lowercased().contains("href=\"data:")
                && !out.contains("href=\"vbscript") && !out.contains("href=\"file:"),
            "\(out)"
        )
        balanced(out)
    }

    @Test func `ordinary links keep their destination and their title`() {
        let out = html(
            "[a](https://example.com/p?q=1&r=2 \"T \\\"x\\\"\") [b](rel/path.md) [c](#frag) [d](mailto:me@x.y)"
        )
        #expect(out.contains("href=\"https://example.com/p?q=1&amp;r=2\"") && out.contains("title=\"T &quot;x&quot;\""))
        #expect(
            out.contains("href=\"rel/path.md\"") && out.contains("href=\"#frag\"")
                && out.contains("href=\"mailto:me@x.y\"")
        )
        balanced(out)
    }

    @Test func `autolinks become links with the target made`() {
        let out = html("<https://a.b/c> <me@x.y> www.z.com http://q.r")
        #expect(
            out.contains("<a href=\"https://a.b/c\">https://a.b/c</a>")
                && out.contains("<a href=\"mailto:me@x.y\">me@x.y</a>")
        )
        #expect(
            out.contains("<a href=\"http://www.z.com\">www.z.com</a>")
                && out.contains("<a href=\"http://q.r\">http://q.r</a>")
        )
    }

    @Test func `an image is named and not loaded`() {
        let out = html("![the \"alt\"](https://tracker.example/p.png)")
        #expect(
            !out.contains("<img") && !out.contains("tracker.example") && out.contains("class=\"image\"")
                && out.contains("alt")
        )
        balanced(out)
    }

    @Test func `a closed mermaid fence is a figure with an SVG, anything else stays code`() {
        let drawn = html("```mermaid\nflowchart TD\n  A --> B\n```")
        #expect(drawn.hasPrefix("<figure><svg") && drawn.contains(">A<") && !drawn.contains("<pre>"))
        balanced(drawn)
        let refused = html("```mermaid\nnot a diagram at all\n```")
        #expect(refused.contains("<pre><code class=\"language-mermaid\">") && !refused.contains("<svg"))
        let other = html("```text\nflowchart TD\n  A --> B\n```")
        #expect(!other.contains("<svg"))
        var plain = MarkdownHTMLRenderer()
        plain.drawsDiagrams = false
        #expect(
            !plain.body(MarkdownParser.parse(Array("```mermaid\nflowchart TD\n  A --> B\n```".utf8))).contains("<svg")
        )
    }

    @Test func `a diagram whose labels are markup carries none`() {
        let out = html("```mermaid\nflowchart TD\n  A[\"<img src=x onerror=alert(1)>\"] --> B\n```")
        #expect(!out.contains("<img") && !out.contains("onerror=\"") && out.contains("&lt;img"))
        balanced(out)
    }

    @Test func `a page has the style, the diagrams' style once, and the content`() {
        let document = MarkdownParser.parse(
            Array("# T\n\n```mermaid\nflowchart TD\n  A --> B\n```\n\n```mermaid\nflowchart TD\n  C --> D\n```".utf8)
        )
        let page = MarkdownHTMLRenderer().page(document, title: "A <b> title")
        #expect(page.hasPrefix("<!DOCTYPE html>") && page.contains("<title>A &lt;b&gt; title</title>"))
        #expect(page.components(separatedBy: "svg.mermaid .n {").count == 2, "the diagrams' sheet is in the page once")
        balanced(page)
    }

    @Test func `controls and bidirectional controls do not reach the page`() {
        let out = html("a\u{202E}b\u{1B}[2Jc\u{0}d")
        #expect(!out.contains("\u{202E}") && !out.contains("\u{1B}") && !out.contains("\u{0}"))
    }

    @Test func `deep nesting is written and balanced`() {
        balanced(html(String(repeating: "> ", count: 200) + "deep"))
        balanced(html(String(repeating: "- ", count: 60) + "deep"))
        balanced(html(String(repeating: "*a ", count: 500)))
        balanced(html(String(repeating: "[", count: 2000) + "x" + String(repeating: "](u)", count: 2000)))
    }

    @Test func `mutated documents always give balanced markup`() {
        let seed = """
            # H *e* [l](https://a.b "t") ![i](x.png)

            > [!NOTE]
            > - [x] a
            >   1. b

            | a | b |
            |---|--:|
            | `c` | <i>d</i> |

            ```mermaid
            flowchart LR
              A -->|x| B
            ```

            [^1]: f<https://x.y>
            """
        var bytes = Array(seed.utf8)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        let noise = Array("*_`[]()<>!|-#>~\n :\"'\\&".utf8)
        for round in 0 ..< 400 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let at = Int(state >> 33) % bytes.count
            switch round % 3 {
                case 0: bytes[at] = noise[Int(state >> 20) % noise.count]
                case 1: bytes.insert(noise[Int(state >> 20) % noise.count], at: at)
                default: if bytes.count > 20 { bytes.remove(at: at) }
            }
            let out = MarkdownHTMLRenderer().body(MarkdownParser.parse(bytes))
            if let problem = TagBalance.problem(in: out) {
                Issue.record(
                    "round \(round): \(problem) for \(String(decoding: bytes, as: UTF8.self).debugDescription)"
                )
                return
            }
            #expect(!out.contains("<script") && !out.contains("javascript:"))
        }
    }
}

@Suite("A Mermaid file as a page")
struct DiagramPageTests {
    @Test func `a diagram is drawn, and one the engine refuses is shown as text`() {
        let drawn = MarkdownHTMLRenderer().diagramPage(Array("flowchart TD\n  A --> B".utf8), title: "d.mmd")
        #expect(drawn.contains("<figure><svg") && TagBalance.problem(in: drawn) == nil)
        let refused = MarkdownHTMLRenderer().diagramPage(Array("<script>alert(1)</script>".utf8), title: "d.mmd")
        #expect(!refused.contains("<svg") && !refused.contains("<script>") && refused.contains("&lt;script&gt;"))
    }
}

@Suite("A diagram as a thumbnail")
struct DiagramThumbnailTests {
    private func render(_ source: String) -> (drawn: Bool, inked: Int) {
        let size = CGSize(width: 200, height: 256)
        guard
            let context = CGContext(
                data: nil,
                width: 200,
                height: 256,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return (false, 0) }
        let drawn = DiagramThumbnail.draw(Array(source.utf8), in: context, size: size)
        guard let data = context.data else { return (drawn, 0) }
        let pixels = unsafe UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: 200 * 256)
        return (drawn, pixels.count { $0 < 200 })
    }

    @Test func `a flowchart puts ink on the page, and a text that is no diagram does not`() {
        let flowchart = render("flowchart TD\n  A --> B")
        #expect(flowchart.drawn && flowchart.inked > 200)
        #expect(!render("this is prose, not a diagram").drawn)
    }
}
