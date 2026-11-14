import AppKit
import Observation
import Testing
import os

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

    @Test func `the page is made when it is asked for, not at each edit`() {
        let source = MarkdownSource(text: "# One\n\ntext\n")
        #expect(source.pagesMade == 0, "a source nobody shows rendered makes no page")
        for index in 0 ..< 10 { source.storage.replaceCharacters(in: NSRange(location: index, length: 0), with: "x") }
        #expect(source.pagesMade == 0 && source.revision == 10)
        #expect(source.document.rows.count == 2 && source.document.rows.count == 2 && source.pagesMade == 1)
        source.storage.replaceCharacters(in: NSRange(location: source.storage.length, length: 0), with: "\n## Two\n")
        #expect(source.pagesMade == 1 && source.document.rows.count == 3 && source.pagesMade == 2)
        source.settings.showsLanguage.toggle()
        #expect(source.pagesMade == 2)
        _ = source.document
        #expect(source.pagesMade == 3, "other settings make another page")
    }

    @Test func `what shows the page is told when the text or the settings change`() {
        let source = MarkdownSource(text: "one\n")
        let told = OSAllocatedUnfairLock(initialState: 0)
        func watch() {
            withObservationTracking {
                _ = source.document
            } onChange: {
                told.withLock { $0 += 1 }
            }
        }
        watch()
        source.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
        #expect(told.withLock { $0 } == 1)
        watch()
        source.settings.showsLanguage.toggle()
        #expect(told.withLock { $0 } == 2)
    }

    @Test func `plain text is held and edited without being read as Markdown`() {
        let source = MarkdownSource(text: "# not a heading\n* not a list\n", content: .plain)
        #expect(source.content == .plain && !source.isDiagram && source.document.rows.isEmpty && source.pagesMade == 0)
        source.storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "//")
        #expect(source.text == "// not a heading\n* not a list\n" && source.isEdited && source.revision == 1)
        #expect(source.lastEdit == nil && source.session.utf8Count == 0, "the parser is not run on it")
        source.undoManager.undo()
        source.markSaved()
        #expect(!source.isEdited)
        #expect(MarkdownSource(text: "flowchart LR\n", isDiagram: true).content == .diagram)
        #expect(MarkdownSource(text: "a").content == .markdown)
    }
}
