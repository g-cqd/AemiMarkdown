import AemiMarkdown
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import MarkdownLookKit

/// Pictures in a document (ADR-0010): a paragraph that is one image is a row of its own, read from a local file and from
/// nowhere else; what the host does with a link.
@MainActor
@Suite("Pictures and links of a native document")
struct NativeImageTests {
    private func rows(_ source: String) -> [NativeRow] {
        NativeDocument(MarkdownParser.parse(Array(source.utf8))).rows
    }

    private func picture(_ row: NativeRow) -> NativeImage? {
        if case .image(let image) = row.content { return image }
        return nil
    }

    @Test func `a paragraph that is one image is an image row; an image among words stays text`() {
        let found = rows(
            "![A chart](img/chart.png)\n\nsee ![x](a.png) here\n\n[![badge](b.png)](https://example.org)\n"
        )
        #expect(found.count == 3)
        #expect(picture(found[0])?.source == "img/chart.png" && picture(found[0])?.alt == "A chart")
        #expect(picture(found[0]).map { String($0.fallback.characters) }?.contains("A chart") == true)
        #expect(picture(found[1]) == nil, "an image in a sentence is named, as before")
        #expect(picture(found[2])?.source == "b.png" && picture(found[2])?.link == URL(string: "https://example.org"))
        #expect(found[0].source == "![A chart](img/chart.png)")
    }

    @Test func `a picture is a local file and nothing else`() {
        let base = URL(fileURLWithPath: "/tmp/doc", isDirectory: true)
        func file(_ source: String, _ base: URL?) -> String? {
            NativeImage(source: source, alt: "", fallback: AttributedString()).file(base: base)?.path
        }
        #expect(file("img/a.png", base) == "/tmp/doc/img/a.png")
        #expect(file("../a%20b.png?raw=1#top", base) == "/tmp/a b.png")
        #expect(file("/abs/a.png", nil) == "/abs/a.png" && file("file:///abs/a.png", nil) == "/abs/a.png")
        #expect(file("a.png", nil) == nil, "a relative picture needs the document's folder")
        #expect(file("https://example.org/a.png", base) == nil && file("//example.org/a.png", base) == nil)
        #expect(file("data:image/png;base64,AAAA", base) == nil && file("file://server/share/a.png", base) == nil)
        #expect(file("", base) == nil)
    }

    private func png(width: Int, height: Int, at path: String) throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = URL(fileURLWithPath: path) as CFURL
        let destination = try #require(CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func `a picture is read off the main actor, no larger than asked, and what is not a picture is nothing`()
        async throws
    {
        let folder = NSTemporaryDirectory() + "pictures-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try png(width: 400, height: 200, at: folder + "/a.png")
        try "not a picture".write(toFile: folder + "/b.png", atomically: true, encoding: .utf8)
        let whole = try #require(await NativeImageLoader.load(URL(fileURLWithPath: folder + "/a.png")))
        #expect(whole.image.width == 400 && whole.size == CGSize(width: 400, height: 200))
        let small = try #require(
            await NativeImageLoader.load(URL(fileURLWithPath: folder + "/a.png"), longestSide: 100)
        )
        #expect(small.image.width == 100 && small.image.height == 50, "decoded no larger than it is drawn")
        #expect(small.size == CGSize(width: 400, height: 200), "its size on the page is the picture's own")
        #expect(await NativeImageLoader.load(URL(fileURLWithPath: folder + "/b.png")) == nil)
        #expect(await NativeImageLoader.load(URL(fileURLWithPath: folder + "/none.png")) == nil)
        #expect(await NativeImageLoader.load(URL(fileURLWithPath: folder + "/a.png"), largestFile: 10) == nil)
    }

    @Test func `a link goes to the host when it takes links, resolved against the document's folder`() throws {
        let base = URL(fileURLWithPath: "/tmp/doc", isDirectory: true)
        let other = try #require(URL(string: "notes/other.md#part"))
        #expect(
            NativeLinkRoute(other, base: base, hostTakesLinks: true)
                == .host(URL(fileURLWithPath: "/tmp/doc/notes/other.md"))
        )
        #expect(NativeLinkRoute(other, base: nil, hostTakesLinks: true) == .nothing)
        let web = try #require(URL(string: "https://example.org/a"))
        #expect(NativeLinkRoute(web, base: base, hostTakesLinks: true) == .host(web))
        #expect(NativeLinkRoute(web, base: base, hostTakesLinks: false) == .system, "with no host, as before")
        #expect(NativeLinkRoute(other, base: base, hostTakesLinks: false) == .nothing)
        let note = try #require(NativeLink.url(NativeLink.note, label: "1"))
        #expect(NativeLinkRoute(note, base: base, hostTakesLinks: true) == .note("1"))
        let back = try #require(NativeLink.url(NativeLink.reference, label: "1"))
        #expect(NativeLinkRoute(back, base: base, hostTakesLinks: true) == .reference("1"))
        let anchor = try #require(URL(string: "#top"))
        #expect(
            NativeLinkRoute(anchor, base: base, hostTakesLinks: true) == .nothing,
            "a place in the page: not done yet"
        )
    }

    @Test func `text that is not Markdown is not coloured as Markdown`() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let plain = MarkdownSource(text: "# not a heading **not bold**\n", content: .plain)
        MarkdownSourceHighlight.apply(
            to: plain,
            font: font,
            visible: NSRange(location: 0, length: plain.storage.length)
        )
        var range = NSRange()
        let colour = plain.storage.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
        #expect(colour == .labelColor && range.length == plain.storage.length, "one colour from end to end")
        #expect(plain.storage.attribute(.font, at: 20, effectiveRange: nil) as? NSFont == font)
        #expect(plain.revision == 0 && !plain.isEdited, "colouring is not an edit")
        let markdown = MarkdownSource(text: "# a heading\n")
        MarkdownSourceHighlight.apply(to: markdown, font: font, visible: NSRange(location: 0, length: 12))
        #expect(
            markdown.storage.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor == .controlAccentColor
        )
    }

    @Test func `an editor says when it has the keyboard, so a host knows which pane was clicked`() {
        let source = MarkdownSource(text: "text")
        let proxy = MarkdownEditorProxy()
        let coordinator = MarkdownSourceEditorCoordinator(source: source, configuration: .init())
        let view = MarkdownSourceEditor.makeTextView(for: source, configuration: .init())
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        scroll.documentView = view
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scroll
        coordinator.attach(view, in: scroll, proxy: proxy)
        #expect(!proxy.isFocused)
        #expect(window.makeFirstResponder(view) && proxy.isFocused)
        #expect(window.makeFirstResponder(nil) && !proxy.isFocused)
        coordinator.detach()
    }
}
