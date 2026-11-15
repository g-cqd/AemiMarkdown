import AemiMarkdown
import AppKit
import Foundation
import Observation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// A document that changes while it is shown, as it does beside its own source: the rows are drawn again before the selection reads them.
@MainActor @Suite("The native selection, under a document that changes", .serialized)
struct NativeSelectionChangeTests {
    @Observable final class Holder {
        var document: NativeDocument
        init(_ document: NativeDocument) { self.document = document }
    }

    struct Page: View {
        let holder: Holder
        let selection: DocumentSelection

        var body: some View {
            NativeDocumentView(document: holder.document, settings: ViewerSettings(), selection: selection)
        }
    }

    private func document(_ source: String) -> NativeDocument {
        NativeDocument(MarkdownParser.parse(Array(source.utf8)))
    }

    private func settle() async {
        for _ in 0 ..< 12 { try? await Task.sleep(for: .milliseconds(25)) }
    }

    private func click(at point: CGPoint, in window: NSWindow, clicks: Int) {
        guard let content = window.contentView else { return }
        let at = CGPoint(x: point.x, y: content.bounds.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type,
                location: at,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: clicks,
                pressure: 1
            ) {
                window.sendEvent(event)
            }
        }
    }

    @Test func `a row the selection has not read yet is not selected`() {
        let selection = DocumentSelection(document: document("a\n\n```\nx\n```\n\nb"))
        selection.selectAll()
        // The row a longer document has, asked about before `load`: as a row view does when it is drawn first.
        #expect(!selection.covers(row: 3) && selection.range(row: 3) == nil)
        selection.frames[3] = CGRect(x: 0, y: 900, width: 100, height: 20)
        #expect(selection.point(at: CGPoint(x: 10, y: 910)) == nil, "nor is it a place a press can be at")
        selection.anchor = SelectionPoint(row: 5, offset: 0)
        selection.focus = SelectionPoint(row: 6, offset: 1)
        #expect(selection.text == nil)
    }

    @Test
    func `a document that grows under a selection is drawn, loses the selection, and is selected again by a click`()
        async
    {
        _ = NSApplication.shared
        let short = "alpha beta gamma\n\n```\nx\n```"
        let holder = Holder(document(short))
        let selection = DocumentSelection(document: holder.document)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Page(holder: holder, selection: selection))
        window.orderBack(nil)
        defer { window.close() }
        await settle()
        selection.selectAll()
        #expect(selection.covers(row: 1))

        holder.document = document(short + "\n\nmore\n\n```\ny\n```")
        await settle()
        #expect(selection.isEmpty, "the selection of the document that was is not one of the document that is")
        #expect(selection.frames.count == 4, "every row on screen has its frame again")

        // The first row did not move: a double click in it still takes its word.
        guard let first = selection.frames[0] else {
            Issue.record("the first row has no frame after the change")
            return
        }
        click(at: CGPoint(x: first.minX + 8, y: first.midY), in: window, clicks: 1)
        click(at: CGPoint(x: first.minX + 8, y: first.midY), in: window, clicks: 2)
        await settle()
        #expect(selection.text == "alpha")
    }
}
