import AemiMarkdown
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// The rows a SwiftUI view lists: containers as guides, space decided, nothing in a document acting.
@Suite("The native document")
struct NativeDocumentTests {
    private func rows(_ source: String, settings: ViewerSettings = ViewerSettings()) -> [NativeRow] {
        NativeDocument(MarkdownParser.parse(Array(source.utf8)), settings: settings).rows
    }

    private func text(_ row: NativeRow) -> String {
        if case .text(let value) = row.content { return String(value.string.characters) }
        return ""
    }

    @Test func `paragraphs and headings are rows with the space the scale gives`() {
        let found = rows("# Title\n\nfirst\n\nsecond\n\n## Next\n\nafter")
        #expect(found.map(text) == ["Title", "first", "second", "Next", "after"])
        #expect(found.map(\.gap) == [0, 0.6, 1, 2.2 * 1.45, 0.6])
        if case .text(let heading) = found[0].content { #expect(heading.style == .heading(1)) }
    }

    @Test func `a quote is a bar that runs on through the rows inside it`() {
        let found = rows("> one\n>\n> two\n\nafter")
        #expect(
            found[0].guides == [.bar(nil, continues: false)] && found[1].guides == [.bar(nil, continues: true)]
                && found[2].guides.isEmpty
        )
        #expect(found[0].gap == 0 && found[1].gap == 1 && found[2].gap == 1.5)
    }

    @Test func `an alert has its title as its first row`() {
        let found = rows("> [!WARNING]\n> careful")
        #expect(
            text(found[0]) == "Warning" && found[0].guides == [.bar(.warning, continues: false)]
                && text(found[1]) == "careful"
        )
        if case .text(let title) = found[0].content { #expect(title.style == .alertTitle) }
    }

    @Test func `list items put a marker on their first row and an indent under it`() {
        let found = rows("1. one\n   more\n\n   para\n2. two\n10. ten")
        #expect(found.map(text) == ["one more", "para", "two", "ten"])
        #expect(
            found[0].guides == [.marker(.number("1."))] && found[1].guides == [.indent]
                && found[2].guides == [.marker(.number("2."))] && found[3].guides == [.marker(.number("3."))]
        )
    }

    @Test func `nesting is a column for each level, and a child is as far below its parent as the next item is`() {
        let found = rows("- a\n- b\n  - c\n    - d\n- e")
        #expect(found.map(text) == ["a", "b", "c", "d", "e"])
        #expect(found.map(\.guides.count) == [1, 1, 2, 3, 1])
        #expect(found[3].guides == [.indent, .indent, .marker(.bullet(depth: 2))])
        #expect(found.dropFirst().allSatisfy { $0.gap == 0.4 }, "\(found.map(\.gap))")
    }

    @Test func `a loose list is spaced by a block, a tight one by a step`() {
        #expect(rows("- a\n\n- b").map(\.gap) == [0, 1])
        #expect(rows("- a\n- b").map(\.gap) == [0, 0.4])
    }

    @Test func `a task takes the place of the marker, in a bulleted and in an ordered list`() {
        let found = rows("- [x] done\n- [ ] open\n1. [ ] first")
        #expect(
            found.map(\.guides) == [
                [.marker(.task(done: true))], [.marker(.task(done: false))], [.marker(.task(done: false))]
            ]
        )
    }

    @Test func `code keeps its language and its raw text, expands tabs, and is coloured`() {
        let found = rows("```swift\nlet x =\t1\n```")
        guard case .code(let code) = found[0].content else {
            Issue.record("not code")
            return
        }
        #expect(code.language == "swift" && code.raw == "let x =\t1" && String(code.shown.characters) == "let x = 1")
        #expect(code.shown.runs.count > 1)
        var plain = ViewerSettings()
        plain.highlightsCode = false
        guard case .code(let uncoloured) = rows("```swift\nlet x = 1\n```", settings: plain)[0].content else { return }
        #expect(uncoloured.shown.runs.count == 1)
    }

    @Test func `tab stops follow the columns`() {
        #expect(
            NativeBuilder.expandTabs("a\tb\n\tc", size: 4) == "a   b\n    c"
                && NativeBuilder.expandTabs("abcd\te", size: 4) == "abcd    e"
        )
    }

    @Test func `boxes are set off by the box step and a rule by the section step`() {
        let found = rows("text\n\n```\ncode\n```\n\nmore\n\n---\n\nlast")
        #expect(found.map(\.gap) == [0, 1.5, 1.5, 2.2, 2.2])
    }

    @Test func `a table keeps its columns, their alignment and its header`() {
        guard case .table(let table) = rows("| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |")[0].content
        else {
            Issue.record("not a table")
            return
        }
        #expect(
            table.alignments == [.leading, .center, .trailing]
                && table.header.map { String($0.characters) } == ["a", "b", "c"] && table.rows.count == 2
        )
    }

    @Test
    func
        `a table is sized as the page sizes it: short columns on a line, long ones to wrap, a wide one beside the text`()
    {
        func table(_ source: String) -> NativeTable? {
            if case .table(let found) = rows(source)[0].content { found } else { nil }
        }
        let long = String(repeating: "word ", count: 12)
        guard let narrow = table("| a | b |\n|---|---|\n| 1 | 2 |"),
            let wide = table("| a | b | c |\n|---|---|---|\n| \(long) | \(long) | \(long) |")
        else {
            Issue.record("not a table")
            return
        }
        let (small, large) = (NativeTableShape(narrow), NativeTableShape(wide))
        #expect(!small.isWide && small.keepsLine(0) && small.keepsLine(1))
        #expect(large.isWide && !large.keepsLine(0) && large.floor(0) == TableLayout.flexibleFloor)
    }

    @Test func `the narrowest a cell can be is its longest piece between spaces and after hyphens`() {
        func width(_ text: String) -> CGFloat {
            NativeTableShape.unbreakable(AttributedString(text), size: 13, codeScale: 0.9, weight: .regular)
        }
        #expect(width("ab cd") < width("abcd"))
        #expect(width("ab-cd") < width("abcd"))
        #expect(width("ab/cd") == width("ab/cd ab"))
    }

    @Test func `the choices of the page about tables and alignment reach its style sheet, and only those`() {
        var settings = ViewerSettings()
        #expect(!settings.css.contains("100vw"))
        settings.bleedsTables = true
        #expect(settings.css.contains("padding-inline") && settings.css.contains("100vw"))
        settings.alignsLeft = true
        #expect(settings.css.contains("main { margin-inline: 0 auto; }"))
    }

    @Test
    func `a table's column widths are shared as the page shares them: short columns on a line, the room in proportion`()
    {
        let grid = NativeTableGrid(columns: 2, keeps: [true, false], floors: [0, 50], available: 300)
        #expect(grid.columns == 2 && grid.available == 300)
    }

    @Test func `fonts reach the style sheet as names and numbers only, and the preferences are read cleanly`() {
        #expect(FontFace("serif") == .serif && FontFace("  ") == .system)
        #expect(FontFace("Evil';}body{x:y") == .family("Evilbodyxy"))
        #expect(
            ViewerFonts.features("ss01, tnum, cv11=2, bad, toolong, x=1, ss02=99").map(\.tag) == [
                "ss01", "tnum", "cv11"
            ]
        )
        var settings = ViewerSettings()
        settings.fonts = ViewerFonts.Preset.serifText.fonts
        settings.fonts.features = ViewerFonts.features("ss01")
        let css = settings.css
        #expect(css.contains("html { font-family: ui-serif"))
        #expect(css.contains("h1, h2, h3, h4, h5, h6 { font-family: -apple-system"))
        #expect(css.contains("font-feature-settings: \"ss01\" 1"))
    }

    @Test
    func
        `the native fonts follow the choices: designs, a named family that is installed, and the system's when it is not`()
    {
        var fonts = ViewerFonts()
        fonts.heading = .serif
        let native = NativeFonts(fonts)
        #expect(native.nsFont(.heading, size: 20).fontDescriptor.symbolicTraits.contains(.italic) == false)
        #expect(native.nsFont(.heading, size: 20).fontName != native.nsFont(.text, size: 20).fontName)
        #expect(native.nsFont(.code, size: 13).isFixedPitch)
        fonts.text = .family("No Such Family Anywhere")
        #expect(NativeFonts(fonts).nsFont(.text, size: 13).fontName == NSFont.systemFont(ofSize: 13).fontName)
        fonts.text = .family("Georgia")
        #expect(NativeFonts(fonts).nsFont(.text, size: 13).familyName == "Georgia")
    }

    @Test func `links keep a safe destination only, and an image is named and not loaded`() {
        func links(_ source: String) -> [URL] {
            rows(source)
                .flatMap { row -> [URL] in
                    if case .text(let t) = row.content { return t.string.runs.compactMap(\.link) }
                    return []
                }
        }
        #expect(links("[a](https://example.com) [b](rel/x.md) [c](mailto:me@x.y)").count == 3)
        for bad in [
            "[x](javascript:alert(1))", "[x](data:text/html,<b>)", "[x](file:///etc/passwd)",
            "[x][r]\n\n[r]: vbscript:y", "<javascript:alert(1)>"
        ] { #expect(links(bad).isEmpty, "\(bad)") }
        let image = rows("![the alt](https://tracker.example/p.png)")
        #expect(text(image[0]).contains("the alt") && links("![the alt](https://tracker.example/p.png)").isEmpty)
    }

    @Test func `autolinks link their target`() {
        let found = rows("<https://a.b> www.z.com")
        guard case .text(let t) = found[0].content else { return }
        #expect(t.string.runs.compactMap(\.link).map(\.absoluteString) == ["https://a.b", "http://www.z.com"])
    }

    @Test func `a footnote reference links to its note and the note back`() {
        let document = NativeDocument(MarkdownParser.parse(Array("a[^n] b[^n]\n\n[^n]: the note\n\nafter".utf8)))
        #expect(document.referenceRow["n"] == 0 && document.noteRow["n"] != nil)
        guard let noteRow = document.noteRow["n"], case .text(let note) = document.rows[noteRow].content else {
            Issue.record("no note")
            return
        }
        #expect(note.back == "n")
        #expect(document.rows.contains { if case .footnoteRule = $0.content { true } else { false } })
        guard case .text(let first) = document.rows[0].content else { return }
        #expect(first.string.runs.compactMap(\.link).allSatisfy { NativeLink.parse($0)?.label == "n" })
        #expect(NativeLink.parse(NativeLink.url(NativeLink.note, label: "a b/é")!)?.label == "a b/é")
    }

    @Test func `a mermaid fence is a diagram, and one the engine refuses is code`() {
        guard case .diagram(.scene) = rows("```mermaid\nflowchart TD\n  A --> B\n```")[0].content else {
            Issue.record("no diagram")
            return
        }
        guard case .diagram(.pie) = rows("```mermaid\npie\n  \"a\" : 1\n  \"b\" : 2\n```")[0].content else {
            Issue.record("no pie")
            return
        }
        if case .code = rows("```mermaid\nnot a diagram\n```")[0].content {} else { Issue.record("not code") }
        var off = ViewerSettings()
        off.drawsDiagrams = false
        if case .code = rows("```mermaid\nflowchart TD\n  A --> B\n```", settings: off)[0].content {
        } else {
            Issue.record("drawn though off")
        }
    }

    @Test func `smart punctuation touches prose and not code`() {
        #expect(
            text(rows("say \"hi\" it's...")[0]) == "say “hi” it’s…" && text(rows("say `\"hi\"`")[0]) == "say \"hi\""
        )
        var off = ViewerSettings()
        off.smartPunctuation = false
        #expect(text(rows("say \"hi\"", settings: off)[0]) == "say \"hi\"")
    }

    @Test func `deep and hostile documents are read in one pass and every row has an id in order`() {
        for source in [
            String(repeating: "> ", count: 200) + "deep", String(repeating: "- ", count: 60) + "deep",
            String(repeating: "*a ", count: 500),
            String(repeating: "[", count: 2000) + "x" + String(repeating: "](u)", count: 2000)
        ] {
            let found = rows(source)
            #expect(found.enumerated().allSatisfy { $0.offset == $0.element.id })
        }
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var bytes = Array(
            "# H *e* [l](https://a.b)\n\n> [!NOTE]\n> - [x] a\n>   1. b\n\n| a | b |\n|---|--:|\n| `c` | d |\n\n```mermaid\nflowchart LR\n  A -->|x| B\n```\n\n[^1]: f"
                .utf8
        )
        let noise = Array("*_`[]()<>!|-#>~\n :\"'\\&".utf8)
        for round in 0 ..< 300 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let at = Int(state >> 33) % bytes.count
            switch round % 3 {
                case 0: bytes[at] = noise[Int(state >> 20) % noise.count]
                case 1: bytes.insert(noise[Int(state >> 20) % noise.count], at: at)
                default: if bytes.count > 20 { bytes.remove(at: at) }
            }
            let found = NativeDocument(MarkdownParser.parse(bytes)).rows
            #expect(found.enumerated().allSatisfy { $0.offset == $0.element.id })
        }
    }

    @Test func `the public corpus reads as rows`() throws {
        let directory =
            (ProcessInfo.processInfo.environment["AEMI_MARKDOWN_CORPUS"]
                ?? NSString(string: "~/Library/Caches/AemiMarkdownCorpus").expandingTildeInPath) + "/files"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted().prefix(150)
        guard !names.isEmpty else { return }
        var total = 0
        for name in names {
            guard let data = FileManager.default.contents(atPath: directory + "/" + name), data.count < 300_000 else {
                continue
            }
            total += NativeDocument(MarkdownParser.parse(Array(data))).rows.count
        }
        #expect(total > 1000)
    }
}
