import AppKit
import Testing

@testable import MarkdownLookKit

@MainActor
@Suite("One text behind every view of a document")
struct MarkdownSourceTests {
    @Test func `an edit of the storage, by any view, is read into the session and the page`() {
        let source = MarkdownSource(text: "# One\n\ntext 😀 here\n")
        #expect(source.text == "# One\n\ntext 😀 here\n" && source.revision == 0 && !source.isEdited)
        let rows = source.document.rows.count
        source.storage.replaceCharacters(in: NSRange(location: 14, length: 0), with: "é")
        #expect(source.text == "# One\n\ntext 😀é here\n")
        #expect(source.session.text == source.text, "the parser holds the same text as the views")
        #expect(source.revision == 1 && source.isEdited && source.document.rows.count == rows)
        source.storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "Plain")
        #expect(source.session.text == "Plain\n\ntext 😀é here\n" && source.revision == 2)
    }

    @Test func `colouring the storage is not an edit`() {
        let source = MarkdownSource(text: "a **b**")
        MarkdownSourceHighlight.apply(to: source.storage, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(source.revision == 0 && !source.isEdited)
    }

    @Test func `a command is one undoable edit; undone back to what was saved, the text is not edited`() {
        let source = MarkdownSource(text: "word")
        let selection = source.perform(.bold, selection: 0 ..< 4)
        #expect(source.text == "**word**" && selection == 2 ..< 6 && source.isEdited)
        source.undoManager.undo()
        #expect(source.text == "word" && !source.isEdited && source.session.text == "word")
        source.undoManager.redo()
        #expect(source.text == "**word**" && source.isEdited)
        source.markSaved()
        #expect(!source.isEdited)
        source.undoManager.undo()
        #expect(source.isEdited, "undone past the save, it differs from the file again")
    }

    @Test func `reloading replaces the text, forgets the undo history and counts as saved`() {
        let source = MarkdownSource(text: "a")
        source.perform(.bold, selection: 0 ..< 1)
        source.reload(text: "from disk")
        #expect(source.text == "from disk" && source.session.text == "from disk")
        #expect(!source.isEdited && !source.undoManager.canUndo)
    }

    @Test func `two editors on one source show the same text and share its undo history`() {
        let source = MarkdownSource(text: "shared")
        let first = MarkdownSourceEditor.makeTextView(for: source, configuration: .init())
        let second = MarkdownSourceEditor.makeTextView(for: source, configuration: .init())
        #expect(first.textStorage === source.storage && second.textStorage === source.storage)
        #expect(first.layoutManager !== second.layoutManager)
        first.insertText("both ", replacementRange: NSRange(location: 0, length: 0))
        #expect(second.string == "both shared" && source.session.text == "both shared" && source.revision == 1)
        #expect(source.storage.layoutManagers.count == 2)
        MarkdownSourceEditor.detach(first, from: source)
        #expect(source.storage.layoutManagers.count == 1)
    }

    @Test func `a Mermaid file is one diagram, not Markdown`() {
        let source = MarkdownSource(text: "flowchart LR\n  A --> B\n", isDiagram: true)
        #expect(source.isDiagram && source.document.rows.count == 1)
    }
}
