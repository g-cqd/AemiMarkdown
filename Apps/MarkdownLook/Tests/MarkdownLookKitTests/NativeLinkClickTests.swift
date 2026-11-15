import AemiMarkdown
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// A click on a link among the words of a page, in a window: the page selects by a press, and the press must not take the link's.
@MainActor @Suite("A link of the native page, clicked", .serialized)
struct NativeLinkClickTests {
    final class Taken {
        var links: [URL] = []
    }

    @Test func `a click on a link gives it to the host, and a click beside it does not`() async throws {
        _ = NSApplication.shared
        let source = "The harbour at low tide, as [the other page](other.md) says."
        let document = NativeDocument(MarkdownParser.parse(Array(source.utf8)))
        let selection = DocumentSelection(document: document)
        let taken = Taken()
        let base = URL(fileURLWithPath: "/tmp/pages", isDirectory: true)
        let view = NativeDocumentView(
            document: document,
            settings: ViewerSettings(),
            selection: selection,
            base: base
        ) { taken.links.append($0) }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0 ..< 20 { try? await Task.sleep(for: .milliseconds(25)) }

        // Where the words of the link are: the row's text starts at its origin, and the layout says where each part is.
        let text = "The harbour at low tide, as the other page says."
        let start = try #require(text.range(of: "the other page")).lowerBound.utf16Offset(in: text)
        let geometry = try #require(selection.store.geometry(row: 0))
        let origin = try #require(selection.origins[0])
        let box = try #require(geometry.boxes(from: start, to: start + 14).first)
        let content = try #require(window.contentView)

        func click(_ point: CGPoint) async {
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
                    clickCount: 1,
                    pressure: 1
                ) {
                    window.sendEvent(event)
                }
            }
            for _ in 0 ..< 8 { try? await Task.sleep(for: .milliseconds(25)) }
        }

        await click(CGPoint(x: origin.x + 20, y: origin.y + box.midY))
        #expect(taken.links.isEmpty, "the words before the link are not it")
        await click(CGPoint(x: origin.x + box.midX, y: origin.y + box.midY))
        #expect(taken.links.map(\.path) == ["/tmp/pages/other.md"])
    }
}
