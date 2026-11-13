public import AemiMarkdown
internal import Foundation

/// What one edit of the lab did, for the readout beside the editor.
@available(macOS 26.0, *)
public struct LabEdit: Sendable, Equatable {
    /// Top-level blocks the edit removed and the ones that took their place; a typed letter in a paragraph is one for one.
    public var removedBlocks: Int
    public var insertedBlocks: Int
    /// Whether the edit could not be done in its own region and parsed the whole document.
    public var parsedWhole: Bool
    /// Nanoseconds the edit took in the parser (not the page that is made from it).
    public var nanoseconds: Int
    public var blockCount: Int
}

/// A document being edited in the lab (ADR 0004, ask roadmap 0204): the editor of AemiMarkdown holds it, an edit anywhere is a replacement of bytes, and the page is made from what the editor
/// holds, so the preview is the document as the editor has parsed it after each edit, never a second parse of the text.
@available(macOS 26.0, *)
public struct LabSession: Sendable {
    private var editor: MarkdownEditor
    private var bytes: [UInt8]

    public init(text: String = "") {
        bytes = Array(text.utf8)
        editor = MarkdownEditor(bytes, extensions: MarkdownLook.extensions)
    }

    public var text: String { String(decoding: bytes, as: UTF8.self) }
    public var utf8Count: Int { bytes.count }

    /// Replaces the bytes of `range` (a range of the UTF-8 of the text) with `replacement`. A range outside the text is cut to it.
    @discardableResult
    public mutating func replace(_ range: Range<Int>, with replacement: String) -> LabEdit {
        let lower = Swift.min(Swift.max(range.lowerBound, 0), bytes.count)
        let upper = Swift.min(Swift.max(range.upperBound, lower), bytes.count)
        let inserted = Array(replacement.utf8)
        bytes.replaceSubrange(lower ..< upper, with: inserted)
        let clock = ContinuousClock()
        var change = MarkdownChange(
            replaced: lower ..< upper,
            insertedBytes: 0,
            firstBlock: 0,
            removedBlocks: 0,
            insertedBlocks: 0
        )
        let elapsed = clock.measure { change = editor.replace(lower ..< upper, with: inserted) }
        let parts = elapsed.components
        return LabEdit(
            removedBlocks: change.removedBlocks,
            insertedBlocks: change.insertedBlocks,
            parsedWhole: editor.lastEditParsedWhole,
            nanoseconds: Int(parts.seconds) * 1_000_000_000 + Int(parts.attoseconds / 1_000_000_000),
            blockCount: editor.document.blockCount
        )
    }

    /// The document as it stands, as the rows a view draws.
    public func nativeDocument(settings: ViewerSettings) -> NativeDocument {
        NativeDocument(editor.document, settings: settings)
    }

    /// The page of the document as it stands.
    public func page(title: String, settings: ViewerSettings) -> String {
        MarkdownHTMLRenderer(settings: settings).page(editor.document, title: title)
    }

    /// The UTF-8 offset of a UTF-16 offset of the text (what a text view reports): one pass over the bytes up to it, nothing
    /// allocated. An offset past the end is the end.
    /// - Complexity: O(the bytes before the offset).
    public func utf8Offset(ofUTF16 offset: Int) -> Int {
        var units = 0
        var index = 0
        while index < bytes.count, units < offset {
            let lead = bytes[index]
            let width = lead < 0x80 ? 1 : (lead < 0xE0 ? 2 : (lead < 0xF0 ? 3 : 4))
            // A scalar of four bytes is two UTF-16 units; every other one is one.
            units += width == 4 ? 2 : 1
            index += width
        }
        return Swift.min(index, bytes.count)
    }
}
