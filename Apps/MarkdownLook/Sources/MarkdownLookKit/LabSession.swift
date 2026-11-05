public import AemiMarkdown
internal import Foundation

/// What one edit of the lab did, for the readout beside the editor.
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
public struct LabSession: Sendable {
    private var editor: MarkdownEditor
    private var bytes: [UInt8]

    public init(text: String = "") {
        bytes = Array(text.utf8)
        editor = MarkdownEditor(bytes)
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

    /// The UTF-8 offset of a UTF-16 offset of the text (what a text view reports), in one pass over the text up to it.
    public func utf8Offset(ofUTF16 offset: Int) -> Int {
        var units = 0
        var offsetBytes = 0
        for scalar in text.unicodeScalars {
            if units >= offset { break }
            units += scalar.value > 0xFFFF ? 2 : 1
            offsetBytes += scalar.value < 0x80 ? 1 : (scalar.value < 0x800 ? 2 : (scalar.value < 0x10000 ? 3 : 4))
        }
        return offsetBytes
    }
}
