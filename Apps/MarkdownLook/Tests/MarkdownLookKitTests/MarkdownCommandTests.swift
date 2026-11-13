import Testing

@testable import MarkdownLookKit

@Suite("Formatting commands as edits of the source")
struct MarkdownCommandTests {
    /// Applies a command to `text` with `|` marking the selection's ends (one `|`: a caret), and gives the result marked the same way.
    private func run(_ command: MarkdownCommand, _ marked: String) -> String {
        let parts = marked.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let text = parts.joined()
        let low = parts[0].utf16.count
        let high = parts.count > 2 ? low + parts[1].utf16.count : low
        let edit = command.edit(in: text, selection: low ..< high)
        var units = Array(text.utf16)
        units.replaceSubrange(edit.range, with: Array(edit.replacement.utf16))
        var result = units
        result.insert(contentsOf: Array("|".utf16), at: edit.selection.upperBound)
        if !edit.selection.isEmpty { result.insert(contentsOf: Array("|".utf16), at: edit.selection.lowerBound) }
        return String(decoding: result, as: UTF16.self)
    }

    @Test func `bold wraps the selection, and unwraps it when it is wrapped already`() {
        #expect(run(.bold, "a |word| b") == "a **|word|** b")
        #expect(run(.bold, "a **|word|** b") == "a |word| b")
        #expect(run(.bold, "a |**word**| b") == "a |word| b")
    }

    @Test func `with nothing selected the markers are typed and the caret waits between them`() {
        #expect(run(.italic, "a | b") == "a _|_ b")
        #expect(run(.code, "|") == "`|`")
        #expect(run(.strikethrough, "x|") == "x~~|~~")
    }

    @Test func `a link takes the selection as its text and selects where the address goes`() {
        #expect(run(.link, "see |this|.") == "see [this](|url|).")
        #expect(run(.link, "see |.") == "see [|text|](url).")
    }

    @Test func `a heading sets the level of every selected line, and takes it away when it is that level already`() {
        #expect(run(.heading(2), "|Title") == "|## Title|")
        #expect(run(.heading(2), "# Ti|tle") == "|## Title|")
        #expect(run(.heading(2), "## Ti|tle") == "|Title|")
        #expect(run(.heading(1), "a\n|b\nc|\nd") == "a\n|# b\n# c|\nd")
    }

    @Test func `lists and quotes mark each selected line, and unmark them when all are marked`() {
        #expect(run(.bulletList, "|a\nb|") == "|- a\n- b|")
        #expect(run(.bulletList, "|- a\n- b|") == "|a\nb|")
        #expect(run(.numberedList, "|a\nb\nc|") == "|1. a\n2. b\n3. c|")
        #expect(run(.numberedList, "|1. a\n2. b|") == "|a\nb|")
        #expect(run(.taskList, "a|") == "|- [ ] a|")
        #expect(run(.quote, "|a\n\nb|") == "|> a\n>\n> b|")
        #expect(run(.quote, "|> a\n>\n> b|") == "|a\n\nb|")
    }

    @Test func `a list of one kind becomes the other; indentation is kept`() {
        #expect(run(.numberedList, "|- a\n- b|") == "|1. a\n2. b|")
        #expect(run(.bulletList, "  |x") == "|  - x|")
        #expect(run(.taskList, "|- a|") == "|- [ ] a|")
    }

    @Test func `a code block fences the selected lines, and takes the fences away`() {
        #expect(run(.codeBlock, "a\n|b\nc|\nd") == "a\n|```\nb\nc\n```|\nd")
        #expect(run(.codeBlock, "|```\nb\n```|") == "|b|")
    }

    @Test func `offsets are UTF-16 units, as a text view counts; a selection outside the text is cut to it`() {
        #expect(run(.bold, "😀 |é| 😀") == "😀 **|é|** 😀")
        let edit = MarkdownCommand.bold.edit(in: "ab", selection: 5 ..< 9)
        #expect(edit.range == 2 ..< 2 && edit.replacement == "****" && edit.selection == 4 ..< 4)
    }
}
