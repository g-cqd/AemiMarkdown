import AemiMarkdown
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// The selection of a document across its rows: what it covers, and what it copies.
@MainActor @Suite("The native selection")
struct NativeSelectionTests {
    private func document(_ source: String) -> NativeDocument {
        NativeDocument(MarkdownParser.parse(Array(source.utf8)))
    }

    @Test func `rows keep the Markdown they were read from, whole lines and fences included`() {
        let found = document(
            "# Title\n\nsome *text* here\n\n- one\n- two\n\n```swift\nlet a = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---"
        )
        #expect(
            found.rows.map(\.source) == [
                "# Title", "some *text* here", "- one", "- two", "```swift\nlet a = 1\n```",
                "| a | b |\n|---|---|\n| 1 | 2 |", "---"
            ]
        )
    }

    @Test
    func `a selection across rows copies the Markdown of the rows it covers whole and the text of the ends in part`() {
        let selection = DocumentSelection(document: document("# Title\n\nsome *text* here\n\nlast words"))
        selection.anchor = SelectionPoint(row: 0, offset: 2)
        selection.focus = SelectionPoint(row: 2, offset: 4)
        #expect(selection.text == "tle\n\nsome *text* here\n\nlast")
        selection.anchor = SelectionPoint(row: 0, offset: 0)
        selection.focus = SelectionPoint(row: 1, offset: 4)
        #expect(selection.text == "# Title\n\nsome")
    }

    @Test func `select all covers every row and a click elsewhere takes it back`() {
        let found = document("a\n\n```\nx\n```\n\nb")
        let selection = DocumentSelection(document: found)
        selection.selectAll()
        #expect(
            selection.text == "a\n\n```\nx\n```\n\nb" && selection.covers(row: 1) && selection.range(row: 0) == 0 ..< 1
        )
        selection.clear()
        #expect(selection.text == nil && !selection.covers(row: 1))
    }

    @Test func `a block that is not text is selected whole or not at all`() {
        let selection = DocumentSelection(document: document("a\n\n```\nx\n```\n\nb"))
        selection.anchor = SelectionPoint(row: 0, offset: 0)
        selection.focus = SelectionPoint(row: 1, offset: 0)
        #expect(!selection.covers(row: 1))
        selection.focus = SelectionPoint(row: 1, offset: 1)
        #expect(selection.covers(row: 1) && selection.text == "a\n\n```\nx\n```")
    }

    @Test func `text as laid out maps back to the text as written, across code edges and breaks`() {
        let written = AttributedString("a x-y b")
        var text = written
        let code = text.range(of: "x-y")!
        text[code].inlinePresentationIntent = .code
        let rich = NativeRichText.text(text, size: 13)
        // "a ", an edge, "x-", a break mark, "y", an edge, " b", and the end: the marks sit at the edge of what they pad.
        #expect(rich.map == [0, 1, 2, 2, 3, 4, 4, 5, 5, 6, 7])
        #expect(zip(rich.map, rich.map.dropFirst()).allSatisfy { $0 <= $1 })
    }
}

/// The view driven by events sent to a window of its own, which never comes to the front and so does not touch the pointer or the keyboard.
@MainActor @Suite("The native selection, in a window", .serialized)
struct NativeSelectionWindowTests {
    private func host(_ source: String, size: CGSize = CGSize(width: 700, height: 500)) async -> (
        NSWindow, DocumentSelection
    ) {
        _ = NSApplication.shared
        let document = NativeDocument(MarkdownParser.parse(Array(source.utf8)))
        let selection = DocumentSelection(document: document)
        let view = NativeDocumentView(document: document, settings: ViewerSettings(), selection: selection)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        for _ in 0 ..< 20 { try? await Task.sleep(for: .milliseconds(25)) }
        return (window, selection)
    }

    private func send(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow, clicks: Int = 1) {
        // A point in the page's top-left coordinates, as the window wants it from the bottom.
        let at = CGPoint(x: point.x, y: window.contentView!.bounds.height - point.y)
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

    @Test func `a drag from one paragraph to another selects across them`() async {
        let (window, selection) = await host("first paragraph of text\n\nsecond paragraph of text\n\nthird")
        defer { window.close() }
        let frames = selection.frames.sorted { $0.key < $1.key }
        #expect(frames.count >= 3)
        guard frames.count >= 3 else { return }
        let from = CGPoint(x: frames[0].value.minX + 30, y: frames[0].value.midY)
        let to = CGPoint(x: frames[1].value.minX + 60, y: frames[1].value.midY)
        send(.leftMouseDown, at: from, in: window)
        for step in 1 ... 6 {
            let t = CGFloat(step) / 6
            send(
                .leftMouseDragged,
                at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t),
                in: window
            )
            try? await Task.sleep(for: .milliseconds(20))
        }
        send(.leftMouseUp, at: to, in: window)
        try? await Task.sleep(for: .milliseconds(100))
        let copied = selection.text ?? ""
        #expect(copied.hasPrefix("graph of text\n\nsecond par") || copied.contains("\n\nsecond "))
        #expect(selection.start?.row == 0 && selection.end?.row == 1)
        if let view = window.contentView, ProcessInfo.processInfo.environment["SELECTION_PNG"] != nil,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/ql/selection.png"))
        }
    }

    @Test func `a double click takes a word and a third click the paragraph`() async {
        let (window, selection) = await host("alpha beta gamma\n\nsecond")
        defer { window.close() }
        guard let frame = selection.frames[0] else {
            Issue.record("no frame")
            return
        }
        let at = CGPoint(x: frame.minX + 55, y: frame.midY)
        for count in 1 ... 2 {
            send(.leftMouseDown, at: at, in: window, clicks: count)
            try? await Task.sleep(for: .milliseconds(40))
            send(.leftMouseUp, at: at, in: window, clicks: count)
            try? await Task.sleep(for: .milliseconds(40))
        }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(selection.text == "beta")
        send(.leftMouseDown, at: at, in: window, clicks: 3)
        try? await Task.sleep(for: .milliseconds(40))
        send(.leftMouseUp, at: at, in: window, clicks: 3)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(selection.text == "alpha beta gamma")
    }
}
