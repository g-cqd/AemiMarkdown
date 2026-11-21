import AemiMarkdown
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// A selection starts wherever the press is on the page (the owner, 2026-11-21: "Selecting text from rendering can't start from
/// wherever on the rendered page"): in the margin beside the text or below the last block.
@MainActor @Suite("A press anywhere on the native page starts a selection", .serialized)
struct NativeSelectionPressTests {
    private struct Page {
        let window: NSWindow
        let selection: DocumentSelection
        var content: NSView { window.contentView! }  // swiftlint:disable:this force_unwrapping
    }

    private func page(_ source: String) async -> Page {
        _ = NSApplication.shared
        let document = NativeDocument(MarkdownParser.parse(Array(source.utf8)))
        let selection = DocumentSelection(document: document)
        let view = NativeDocumentView(document: document, settings: ViewerSettings(), selection: selection)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        for _ in 0 ..< 20 { try? await Task.sleep(for: .milliseconds(25)) }
        return Page(window: window, selection: selection)
    }

    /// A press at `from`, a drag to `to` and a release, in the page's coordinates (y down).
    private func drag(on page: Page, from: CGPoint, to: CGPoint) async {
        let height = page.content.bounds.height
        let steps: [(NSEvent.EventType, CGPoint)] = [
            (.leftMouseDown, from), (.leftMouseDragged, CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)),
            (.leftMouseDragged, to), (.leftMouseUp, to)
        ]
        for (type, point) in steps {
            if let event = NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: point.x, y: height - point.y),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: page.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) {
                page.window.sendEvent(event)
            }
            for _ in 0 ..< 4 { try? await Task.sleep(for: .milliseconds(25)) }
        }
    }

    private static let source = "First paragraph, a few words long.\n\nSecond paragraph, a few words long.\n\nThird."

    @Test func `a drag from the margin beside the text selects`() async throws {
        let page = await page(Self.source)
        defer { page.window.close() }
        let first = try #require(page.selection.frames[0])
        let third = try #require(page.selection.frames[2])
        await drag(on: page, from: CGPoint(x: 6, y: first.midY), to: CGPoint(x: third.maxX - 2, y: third.midY))
        #expect(page.selection.text?.hasPrefix("First paragraph") == true)
    }

    @Test func `a drag from below the last block selects back up the page`() async throws {
        let page = await page(Self.source)
        defer { page.window.close() }
        let first = try #require(page.selection.frames[0])
        let third = try #require(page.selection.frames[2])
        await drag(
            on: page,
            from: CGPoint(x: third.minX + 20, y: third.maxY + 120),
            to: CGPoint(x: first.minX + 2, y: first.midY)
        )
        #expect(page.selection.text != nil)
    }
}
