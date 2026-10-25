import Testing

@testable import AemiMarkdown

/// What GitHub renders beyond the GFM specification, for which no reference implementation is at hand: alerts and math. Their rules are GitHub's documentation,
/// and each test says one of them (ADR-0001, the conformance paragraph).
@Suite("GitHub alerts and math")
struct GitHubExtensionTests {
    private func outline(_ markdown: String, _ extensions: MarkdownExtensions = .github) -> String {
        Outline.of(MarkdownParser.parse(Array(markdown.utf8), extensions: extensions))
    }

    // MARK: Alerts

    @Test(arguments: [("NOTE", 1), ("tip", 2), ("Important", 3), ("WARNING", 4), ("caution", 5)])
    func `a block quote that opens with an alert marker says which alert it is`(type: String, number: Int) {
        let text = outline("> [!\(type)]\n> Useful information.")
        #expect(text == "blockQuote[\(number)]\n  paragraph\n    text \"Useful information.\"")
    }

    @Test func `an alert marker alone is an alert with no text`() {
        #expect(outline("> [!WARNING]") == "blockQuote[4]")
    }

    @Test func `an alert may be in a list item, and have several blocks`() {
        let text = outline("- > [!NOTE]\n  > one\n  >\n  > two")
        #expect(text.contains("blockQuote[1]"))
        #expect(text.contains("text \"one\""))
        #expect(text.contains("text \"two\""))
    }

    @Test(arguments: [
        "> [!NOTE] text on the same line", "> a line first\n> [!NOTE]\n> more", "> [!FOO]\n> text",
        "> [!NOTE]]\n> text", "[!NOTE]\ntext", "> [! NOTE]\n> text",
        "> [!NOTE\n> text"
    ])
    func `anything else stays an ordinary block quote with its text`(markdown: String) {
        let text = outline(markdown)
        #expect(!text.contains("blockQuote["), "\(markdown.debugDescription) became an alert")
        #expect(text.contains("[") || text.contains("text"))
    }

    @Test func `without the extension the marker is text`() {
        let text = outline("> [!NOTE]\n> x", .gfm)
        #expect(!text.contains("blockQuote["))
        #expect(text.contains("!NOTE"))
    }

    // MARK: Math

    @Test func `dollars around something make inline math, whose text is what lies between`() {
        #expect(outline("a $x^2$ b") == "paragraph\n  text \"a \"\n  math\n    text \"x^2\"\n  text \" b\"")
    }

    @Test func `two dollars make display math, which may run over lines`() {
        let text = outline("$$\na + b\n$$")
        #expect(text.contains("math[1]"))
        #expect(text.contains("text \"a + b\""))
    }

    @Test(arguments: [
        "costs $5 and $6", "$ x $", "a $x $", "$x$5", "an unclosed $x", "just $", "\\$x\\$", "$$", "$$ $$ x"
    ])
    func `a dollar that is not math stays text`(markdown: String) {
        #expect(!outline(markdown).contains("math"), "\(markdown.debugDescription)")
    }

    @Test func `dollars in a code span are code`() {
        #expect(!outline("`$x$`").contains("math"))
    }

    @Test func `without the extension a dollar is text`() {
        #expect(!outline("a $x$ b", .gfm).contains("math"))
    }
}
