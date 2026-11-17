import AppKit
import Testing

@testable import MarkdownLookKit

@MainActor
@Suite("Markdown source colour in the editor")
struct SourceHighlightTests {
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private func storage(_ text: String) -> NSTextStorage {
        let store = NSTextStorage(string: text)
        MarkdownSourceHighlight.apply(to: store, font: font)
        return store
    }

    private func colour(_ store: NSTextStorage, _ unit: Int) -> NSColor? {
        store.attribute(.foregroundColor, at: unit, effectiveRange: nil) as? NSColor
    }

    private func attributeFont(_ store: NSTextStorage, _ unit: Int) -> NSFont? {
        store.attribute(.font, at: unit, effectiveRange: nil) as? NSFont
    }

    @Test func `markers are dimmed, strong is bold, code is plain, and nothing else about the text changes`() {
        let text = "a **b** `c`"
        let store = storage(text)
        #expect(store.string == text)
        #expect(colour(store, 0) == .labelColor, "plain text keeps the label colour")
        #expect(colour(store, 2) == .tertiaryLabelColor, "a ** marker is dimmed")
        #expect(attributeFont(store, 4)?.fontDescriptor.symbolicTraits.contains(.bold) == true, "b is bold")
        #expect(colour(store, 9) == .labelColor, "c is code, in the text's colour")
        // No size change anywhere: lines keep one height.
        for unit in 0 ..< store.length { #expect(attributeFont(store, unit)?.pointSize == 13) }
    }

    @Test func `a heading is tinted and bold at the size of the rest, its hashes dimmed`() {
        let store = storage("## Title")
        #expect(colour(store, 0) == .tertiaryLabelColor)
        #expect(colour(store, 3) == .controlAccentColor)
        #expect(attributeFont(store, 3)?.pointSize == 13)
        #expect(attributeFont(store, 3)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func `emphasis shows even in a face that has no italic`() {
        let store = storage("_e_")
        #expect(
            store.attribute(.obliqueness, at: 1, effectiveRange: nil) != nil
                || attributeFont(store, 1)?.fontDescriptor.symbolicTraits.contains(.italic) == true
        )
    }

    @Test func `text with accents and emoji is styled at the right characters`() {
        // Bytes are not UTF-16 units: "é" is 2 bytes, "🙂" is 4 bytes and 2 units.
        let store = storage("é🙂 **b**")
        let star = (store.string as NSString).range(of: "**").location
        #expect(colour(store, star) == .tertiaryLabelColor)
        #expect(colour(store, star + 2) == .labelColor)
        #expect(attributeFont(store, star + 2)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(colour(store, 0) == .labelColor)
    }

    @Test func `a window re-styles only itself, and clears what it no longer is`() {
        let store = NSTextStorage(string: "**a**\n\n**b**")
        MarkdownSourceHighlight.apply(to: store, font: font)
        #expect(colour(store, 0) == .tertiaryLabelColor)
        // Edit the first line so it is plain, and re-style just it.
        store.replaceCharacters(in: NSRange(location: 0, length: 5), with: "plain")
        MarkdownSourceHighlight.apply(to: store, font: font, window: 0 ..< 5)
        #expect(colour(store, 0) == .labelColor)
        #expect(colour(store, store.length - 5) == .tertiaryLabelColor, "the line outside the window is as it was")
    }

    @Test func `an empty text, a window outside it, and bytes that are not text do not trap`() {
        let empty = NSTextStorage(string: "")
        MarkdownSourceHighlight.apply(to: empty, font: font)
        MarkdownSourceHighlight.apply(to: empty, font: font, window: 5 ..< 9)
        let odd = NSTextStorage(string: "\u{0}*\u{FFFD}* ** `` \u{202E}**x**")
        MarkdownSourceHighlight.apply(to: odd, font: font, window: -3 ..< 1_000)
    }

    private func background(_ store: NSTextStorage, _ unit: Int) -> NSColor? {
        store.attribute(.backgroundColor, at: unit, effectiveRange: nil) as? NSColor
    }

    /// Code is coloured only where its fence names a language a scanner knows, as the page colours it; anything else is in
    /// the text's colour, and no code has a background (Sunset's owner, 2026-11-17: "a background and orange strings … is
    /// not really nice to read").
    @Test func `code is coloured by its language, else plain, never on a background`() {
        let text =
            "```swift\nlet s = \"x\" // c\n```\n\n```zzz\nlet s = \"x\"\n```\n\n    let s = \"x\"\n\na `let s = \"x\"` b\n"
        let store = storage(text)
        let units = Array(text.utf16)
        func unit(of needle: String, from: Int) -> Int {
            let pattern = Array(needle.utf16)
            return (from ..< units.count).first { Array(units[$0 ..< min($0 + pattern.count, units.count)]) == pattern }
                ?? -1
        }
        let swift = unit(of: "let", from: 0)
        let string = unit(of: "\"x\"", from: swift)
        #expect(colour(store, swift) != .labelColor && colour(store, string) != .labelColor)
        #expect(colour(store, swift) != colour(store, string), "a keyword and a string differ")
        #expect(colour(store, unit(of: "= ", from: swift)) == .labelColor, "what no token covers is plain")
        var from = string
        for _ in 0 ..< 3 {
            let other = unit(of: "let", from: from + 1)
            #expect(colour(store, other) == .labelColor && colour(store, unit(of: "\"x\"", from: other)) == .labelColor)
            from = other
        }
        for index in 0 ..< store.length { #expect(background(store, index) == nil, "\(index)") }
    }
}
