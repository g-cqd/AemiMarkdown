import AemiMarkdown
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// A link of the native page has a menu of the host's (Sunset: open in a new tab, beside, in a window, copy): the page
/// knows which link is under the pointer, and gives the host where it leads, as a click would.
@MainActor @Suite("A link of the native page, its menu", .serialized)
struct NativeLinkMenuTests {
    @Test func `the page knows the link under a point, where it leads, and nothing beside it`() async throws {
        _ = NSApplication.shared
        let source = "The harbour at low tide, as [the other page](other.md) says, and [the web](https://example.com)."
        let document = NativeDocument(MarkdownParser.parse(Array(source.utf8)))
        let selection = DocumentSelection(document: document)
        let base = URL(fileURLWithPath: "/tmp/pages", isDirectory: true)
        let view = NativeDocumentView(document: document, settings: ViewerSettings(), selection: selection, base: base)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0 ..< 20 { try? await Task.sleep(for: .milliseconds(25)) }

        let text = "The harbour at low tide, as the other page says, and the web."
        let geometry = try #require(selection.store.geometry(row: 0))
        let origin = try #require(selection.origins[0])
        func middle(of words: String) throws -> CGPoint {
            let start = try #require(text.range(of: words)).lowerBound.utf16Offset(in: text)
            let box = try #require(geometry.boxes(from: start, to: start + words.utf16.count).first)
            return CGPoint(x: origin.x + box.midX, y: origin.y + box.midY)
        }
        #expect(selection.link(at: try middle(of: "harbour")) == nil)
        let file = try #require(selection.link(at: try middle(of: "other page")))
        #expect(
            NativeLinkRoute(file, base: base, hostTakesLinks: true)
                == .host(URL(fileURLWithPath: "/tmp/pages/other.md"))
        )
        #expect(selection.link(at: try middle(of: "the web"))?.absoluteString == "https://example.com")
    }
}

/// What a link's menu is about: where a click would take it, and no menu for a note's link.
@Suite("A link's menu, its target")
struct NativeLinkMenuTargetTests {
    @Test @available(macOS 26.0, *) func `a link's menu is about where a click takes it; a note's link has none`()
        throws
    {
        let base = URL(fileURLWithPath: "/tmp/pages", isDirectory: true)
        let web = try #require(URL(string: "https://example.com/a"))
        #expect(LinkMenuAction.target(of: web, base: base) == web)
        let file = try #require(URL(string: "other.md"))
        #expect(LinkMenuAction.target(of: file, base: base)?.path == "/tmp/pages/other.md")
        let note = try #require(NativeLink.url(NativeLink.note, label: "1"))
        #expect(LinkMenuAction.target(of: note, base: base) == nil)
    }
}
