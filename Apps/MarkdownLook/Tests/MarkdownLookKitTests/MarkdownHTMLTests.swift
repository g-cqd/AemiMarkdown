import AemiMarkdown
import CoreFoundation
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
        #expect(out.contains("<p>A <em>b</em> <strong>c</strong> <del>d</del> <code data-n>e</code></p>"))
        balanced(out)
    }

    @Test func `lists are tight or loose, ordered lists keep their start, and tasks have checkboxes`() {
        #expect(html("- a\n- b").contains("<ul class=\"tight\"><li><p>a</p>"))
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
            out.contains("<thead>") && out.contains("<th data-f class=\"c\">b</th>")
                && out.contains("<td data-f class=\"r\">3</td>")
                && out.contains("<tbody>")
        )
        balanced(out)
    }

    @Test func `alerts, quotes and footnotes`() {
        let alert = html("> [!WARNING]\n> careful")
        #expect(alert.contains("class=\"alert warning\"") && alert.contains(">Warning<") && alert.contains("careful"))
        #expect(html("> plain").contains("<blockquote>"))
        let note = html("a[^1]\n\n[^1]: text")
        #expect(
            note.contains("<sup class=\"fn\"><a href=\"#fn-1\" id=\"fnref-1\">1</a></sup>")
                && note.contains("class=\"footnote\"")
        )
        balanced(alert)
        balanced(note)
    }

    @Test func `code is escaped, tagged with its language, and keeps its quotes straight`() {
        let out = html("```swift\nlet a = \"x\" < 2 && true\n```")
        #expect(out.contains("<pre><code class=\"language-swift\">"))
        #expect(
            out.contains("<span class=\"k\">let</span>")
                && out.contains("&quot;x&quot;</span> &lt; <span class=\"n\">2</span> &amp;&amp;")
        )
        let span = html("say `\"hi\" it's...`")
        #expect(
            span.contains("<code data-n>&quot;hi&quot; it&#39;s...</code>")
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
        let pie = render("pie\n  \"a\" : 3\n  \"b\" : 1")
        #expect(pie.drawn && pie.inked > 1000)
    }
}

@Suite("Table columns")
struct TableLayoutTests {
    private func html(_ source: String) -> String {
        MarkdownHTMLRenderer().body(MarkdownParser.parse(Array(source.utf8)))
    }

    @Test func `a short column stays on one line and a long one may wrap but not below a word`() {
        let long = String(repeating: "word ", count: 30)
        let out = html("| id | text |\n|---|---|\n| UTF-8 | \(long) |")
        #expect(out.contains("<td data-f>UTF-8</td>") && out.contains("<th data-f>id</th>"))
        #expect(out.contains("<td style=\"min-width:12ch\">word"))
    }

    @Test func `the minimum of a long column follows its longest word, within bounds`() {
        let word = String(repeating: "x", count: 50)
        let out = html("| a |\n|---|\n| \(word) \(String(repeating: "y ", count: 20)) |")
        #expect(out.contains("min-width:28ch"))
    }

    @Test func `a table in a box, wide only when its columns need the room`() {
        #expect(html("| a | b |\n|---|---|\n| 1 | 2 |").hasPrefix("<div class=\"table-wrap\"><table>"))
        let wide = html(
            "| \(String(repeating: "a", count: 40)) | \(String(repeating: "b", count: 40)) |\n|---|---|\n| 1 | 2 |"
        )
        #expect(wide.hasPrefix("<div class=\"table-wrap wide\">"))
        #expect(TagBalance.problem(in: wide) == nil)
    }

    @Test func `cells are measured by what shows, not by markup or entities`() {
        let (length, word) = TableLayout.measure("<code data-n>a&amp;b</code> <em>cd</em>".utf8, from: 0)
        #expect(length == 6 && word == 3)
        #expect(TableLayout.measure("héllo wörld".utf8, from: 0) == (11, 5))
    }

    @Test func `rows with fewer or more cells than the header are still sized and balanced`() {
        let out = html("| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |")
        #expect(TagBalance.problem(in: out) == nil)
    }

    @Test func `many tables stay linear`() {
        let table = "| a | b |\n|---|---|\n| 1 | 2 |\n\n"
        let out = html(String(repeating: table, count: 3000))
        #expect(out.components(separatedBy: "<div class=\"table-wrap\">").count == 3001)
    }
}

@Suite("Syntax colour")
struct CodeHighlightTests {
    private func html(_ source: String) -> String {
        MarkdownHTMLRenderer().body(MarkdownParser.parse(Array(source.utf8)))
    }

    @Test(arguments: [
        ("swift", "let x = 1 // note", "k"), ("Swift", "func f() {}", "k"), ("js", "const a = 'x'", "s"),
        ("javascript", "let n = 42", "n"), ("ts", "interface A {}", "k"),
        ("python", "def f(): pass", "k"), ("py", "# hello", "c"), ("bash", "echo \"hi\"", "s"), ("sh", "# c", "c"),
        ("json", "{\"a\": 1}", "n"), ("yml", "a: true", "k"),
        ("html", "<div class=\"a\"></div>", "g"), ("css", "a { color: red; }", "p"), ("rust", "fn main() {}", "k"),
        ("go", "func main() {}", "k"), ("c++", "int x = 3;", "n")
    ])
    func `a known language gets spans`(info: String, code: String, kind: String) {
        let out = html("```\(info)\n\(code)\n```")
        #expect(out.contains("<span class=\"\(kind)\">"), "\(info): \(out)")
        #expect(TagBalance.problem(in: out) == nil)
    }

    @Test func `an unknown language, plain text and no language stay uncoloured`() {
        for info in ["", "text", "plain", "klingon", "mermaidish"] {
            #expect(!html("```\(info)\nlet x = 1\n```").contains(/<span class="[a-z]">/), "\(info)")
        }
    }

    @Test func `the code in the spans is the code, escaped, and nothing a string held acts`() {
        let out = html("```swift\nlet s = \"<script>alert(1)</script> & 'x'\" // <b>\n```")
        #expect(
            !out.contains("<script") && !out.contains("<b>") && out.contains("&lt;script&gt;") && out.contains("&amp;")
        )
        #expect(TagBalance.problem(in: out) == nil)
        let text = out.replacing(/<[^>]+>/, with: "")
        #expect(
            text.contains("let s = &quot;&lt;script&gt;alert(1)&lt;/script&gt; &amp; &#39;x&#39;&quot; // &lt;b&gt;")
        )
    }

    @Test func `a block over the limit is left plain, and one under it is coloured`() {
        let line = "let aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = 1\n"
        let big = String(repeating: line, count: CodeHighlighter.byteLimit / line.utf8.count + 10)
        #expect(!html("```swift\n\(big)```").contains(/<span class="[a-z]">/))
        #expect(html("```swift\n\(line)```").contains(/<span class="[a-z]">/))
    }

    @Test func `source that is not valid for its language still comes out whole and balanced`() {
        let sources = [
            "let \"unterminated", "/* open comment", "'''", "<div", "{\"a\": [1, 2", "a: [", "\\\\\\", "`${`",
            String(repeating: "(", count: 5000)
        ]
        for source in sources {
            for info in ["swift", "js", "python", "html", "json", "yaml", "css", "shell", "rust"] {
                let out = html("```\(info)\n\(source)\n```")
                #expect(TagBalance.problem(in: out) == nil, "\(info) \(source.prefix(20))")
            }
        }
    }

    @Test func `a code span and a diagram are not touched`() {
        #expect(!html("`let x = 1`").contains(/<span class="[a-z]">/))
        #expect(html("```mermaid\nflowchart TD\n  A --> B\n```").contains("<svg"))
    }
}

@Suite("Viewer settings")
struct ViewerSettingsTests {
    private func page(_ settings: ViewerSettings) -> String {
        MarkdownHTMLRenderer(settings: settings).page(MarkdownParser.parse(Array("# T\n\n\tcode".utf8)), title: "t")
    }

    @Test func `numbers are within bounds`() {
        var settings = ViewerSettings()
        settings.tabSize = 99
        settings.textSize = 2
        #expect(settings.tabSize == 8 && settings.textSize == 11)
        #expect(
            page(ViewerSettings(tabSize: 2)).contains("tab-size: 2;") && page(ViewerSettings()).contains("tab-size: 4;")
        )
        #expect(page(settings).contains("font-size: 11px;"))
    }

    @Test func `full width lifts the measure, and the default keeps it`() {
        #expect(page(ViewerSettings(fullWidth: true)).contains("main { max-width: none; }"))
        #expect(!page(ViewerSettings()).contains("main { max-width: none; }"))
    }

    @Test func `table lines are each a choice`() {
        var settings = ViewerSettings()
        #expect(!page(settings).contains("display: none") && !page(settings).contains("td + td::before"))
        settings.rowLines = false
        settings.columnLines = true
        settings.outerBorder = true
        let css = page(settings)
        #expect(
            css.contains("th::after, td::after { display: none; }") && css.contains("td + td::before")
                && css.contains(".table-wrap { border:")
        )
    }

    @Test func `the backdrop is solid only when asked, and a page is transparent otherwise`() {
        var settings = ViewerSettings()
        for mode in [Backdrop.blurred, .clear] {
            settings.backdrop = mode
            #expect(!page(settings).contains("html, body { background: Canvas; }"))
        }
        settings.backdrop = .solid
        #expect(page(settings).contains("html, body { background: Canvas; }"))
    }

    @Test func `code and diagrams follow their switches`() {
        var settings = ViewerSettings()
        settings.highlightsCode = false
        settings.showsLanguage = false
        settings.drawsDiagrams = false
        let out = MarkdownHTMLRenderer(settings: settings)
            .body(
                MarkdownParser.parse(Array("```swift\nlet x = 1\n```\n\n```mermaid\nflowchart TD\n  A --> B\n```".utf8))
            )
        #expect(!out.contains(/<span class="[a-z]">/) && !out.contains("class=\"lang\"") && !out.contains("<svg"))
    }

    @Test func `settings are read from preferences, defaults for what is missing or wrong`() {
        // A domain of the test's own: the reader's real choices are never touched.
        let name = "studio.aemi.MarkdownLook.tests.\(UUID().uuidString)"
        let domain = name as CFString
        defer {
            CFPreferencesSetMultiple(
                nil,
                ["fullWidth", "tabSize", "textSize", "rowLines", "backdrop"] as CFArray,
                domain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        #expect(ViewerSettings.current(domain: name) == ViewerSettings())
        CFPreferencesSetAppValue(ViewerSettings.Key.tabSize as CFString, "wide" as CFString, domain)
        CFPreferencesSetAppValue(ViewerSettings.Key.fullWidth as CFString, kCFBooleanTrue, domain)
        CFPreferencesSetAppValue(ViewerSettings.Key.backdrop as CFString, "sparkly" as CFString, domain)
        CFPreferencesSetAppValue(ViewerSettings.Key.rowLines as CFString, kCFBooleanFalse, domain)
        CFPreferencesSetAppValue(ViewerSettings.Key.textSize as CFString, 99 as CFNumber, domain)
        let read = ViewerSettings.current(domain: name)
        #expect(
            read.fullWidth && read.tabSize == 4 && read.backdrop == .blurred && !read.rowLines && read.textSize == 20
        )
    }

    @Test func `a page allows no request of its own`() {
        #expect(page(ViewerSettings()).contains("default-src 'none'"))
    }
}

@Suite("Footnotes")
struct FootnoteTests {
    private func html(_ source: String) -> String {
        MarkdownHTMLRenderer().body(MarkdownParser.parse(Array(source.utf8)))
    }

    @Test func `a reference links to its definition, which links back to the first reference`() {
        let out = html("a[^n] b[^n]\n\n[^n]: note")
        #expect(out.contains("<a href=\"#fn-n\" id=\"fnref-n\">n</a>") && out.contains("<a href=\"#fn-n\">n</a>"))
        #expect(out.components(separatedBy: "id=\"fnref-n\"").count == 2, "only the first reference has the id")
        #expect(out.contains("id=\"fn-n\"") && out.contains("href=\"#fnref-n\""))
        #expect(TagBalance.problem(in: out) == nil)
    }

    @Test func `definitions sit in one section, and what follows them is outside it`() {
        let out = html("a[^1] b[^2]\n\n[^1]: one\n[^2]: two\n\nafter")
        #expect(out.components(separatedBy: "<section class=\"footnotes\">").count == 2)
        #expect(out.range(of: "</section>")!.upperBound <= out.range(of: "<p>after</p>")!.lowerBound)
        #expect(TagBalance.problem(in: out) == nil)
    }

    @Test func `anchors never collide and never need escaping`() {
        #expect(HTMLWriter.anchor("a b") != HTMLWriter.anchor("a_b") && HTMLWriter.anchor("a\"<>&") == "a_22_3C_3E_26")
        let out = html("x[^a\"b]\n\n[^a\"b]: t")
        #expect(!out.contains("fn-a\"") && TagBalance.problem(in: out) == nil)
    }

    @Test func `a definition nobody references has no way back`() {
        #expect(!html("[^z]: orphan").contains("class=\"back\""))
    }
}

@Suite("Code block label")
struct CodeLabelTests {
    private func html(_ source: String) -> String {
        MarkdownHTMLRenderer().body(MarkdownParser.parse(Array(source.utf8)))
    }

    @Test func `a fence with a language shows it, as text a selection does not take`() {
        let out = html("```swift\nlet x = 1\n```")
        #expect(out.contains("<div class=\"code\"><span class=\"lang\">swift</span><pre>"))
        #expect(!html("```\nplain\n```").contains("class=\"lang\""))
        #expect(!html("<div>x</div>").contains("class=\"lang\""))
    }

    @Test func `the label is escaped like all text`() {
        let out = html("```a<b>\nx\n```")
        #expect(!out.contains("<b>") && out.contains("a&lt;b&gt;"))
    }
}

@Suite("Style policy")
struct StylePolicyTests {
    @Test func `prose boxes hug their text so a selection does, and strokes are rounded`() {
        #expect(ViewerStyle.sheet.contains("width: fit-content; max-width: 100%;"))
        #expect(ViewerStyle.sheet.contains("::selection"))
        // Every drawn bar or rule has a radius.
        for rule in ["hr { border", "blockquote::before", ".footnotes::before", "th:first-child::after"] {
            let lines = ViewerStyle.sheet.split(separator: "\n").filter { $0.contains(rule) }
            #expect(lines.contains { $0.contains("radius") }, "\(rule)")
        }
    }

    @Test func `one indent and one scale drive every nesting and gap`() {
        let sheet = ViewerStyle.sheet
        #expect(sheet.contains("--indent:") && sheet.components(separatedBy: "var(--indent)").count >= 4)
        #expect(
            !sheet.contains("margin: 1.4em") && !sheet.contains("margin: 0.85em"),
            "no stray margin values outside the scale"
        )
    }
}

@Suite("The lab")
struct LabSessionTests {
    private func fresh(_ text: String) -> String {
        MarkdownHTMLRenderer().page(MarkdownParser.parse(Array(text.utf8)), title: "t")
    }

    @Test func `after every edit the page is the page of a fresh parse`() {
        var lab = LabSession(text: "# Title\n\nsome *text* here\n\n- a\n- b\n\n```swift\nlet x = 1\n```\n")
        var model = lab.text
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        let pieces = ["x", "\n", "\n\n", "*", "`", "# ", "- ", "é", "😀", "[l](u)", "```", "| a | b |\n|---|---|\n"]
        for round in 0 ..< 300 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let bytes = Array(model.utf8)
            let from = Int(state >> 33) % (bytes.count + 1)
            let to = Swift.min(bytes.count, from + Int(state >> 20) % 6)
            // Cut at scalar boundaries, as a text view would.
            func boundary(_ i: Int) -> Int {
                var j = Swift.min(i, bytes.count)
                while j > 0, j < bytes.count, bytes[j] & 0xC0 == 0x80 { j -= 1 }
                return j
            }
            let (low, high) = (boundary(from), boundary(to))
            let piece = pieces[Int(state >> 40) % pieces.count]
            var next = bytes
            next.replaceSubrange(low ..< Swift.max(low, high), with: Array(piece.utf8))
            lab.replace(low ..< Swift.max(low, high), with: piece)
            model = String(decoding: next, as: UTF8.self)
            if lab.page(title: "t", settings: ViewerSettings()) != fresh(model) {
                Issue.record("round \(round): the page differs from a fresh parse of \(model.debugDescription)")
                return
            }
        }
    }

    @Test func `a typed letter touches one block and an edit says what it did`() {
        var lab = LabSession(text: "one\n\ntwo\n\nthree\n")
        let edit = lab.replace(5 ..< 5, with: "x")
        #expect(edit.removedBlocks == 1 && edit.insertedBlocks == 1 && edit.blockCount == 3 && !edit.parsedWhole)
        #expect(lab.text == "one\n\nxtwo\n\nthree\n")
    }

    @Test func `a range outside the text is cut to it`() {
        var lab = LabSession(text: "abc")
        lab.replace(2 ..< 99, with: "Z")
        lab.replace(-5 ..< 0, with: ">")
        #expect(lab.text == ">abZ")
    }

    @Test func `utf16 offsets become utf8 offsets`() {
        let lab = LabSession(text: "aé😀z")
        #expect([0, 1, 2, 4, 5].map(lab.utf8Offset(ofUTF16:)) == [0, 1, 3, 7, 8])
    }
}
