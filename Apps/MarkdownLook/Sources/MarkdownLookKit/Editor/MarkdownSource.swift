public import AppKit
public import Observation

/// The one text behind every view of a document (ADR-0008): a text storage that any number of editors show and edit, the undo
/// history they share, the parser's session kept in step with each edit wherever it comes from (a key typed in any editor, a
/// command, undo), and the page made from what the parser holds. Whoever owns a document owns one of these per file; panes are
/// views of it, so two of them can never hold two versions of the text.
@available(macOS 26.0, *)
@MainActor @Observable
public final class MarkdownSource: NSObject, @MainActor NSTextStorageDelegate {
    /// The text as the editors hold it. Change it through an editor, `perform` or `apply`; any change is followed.
    @ObservationIgnored public let storage: NSTextStorage
    /// One history for every editor of this text.
    @ObservationIgnored public let undoManager = UndoManager()
    /// A Mermaid file is one diagram, not Markdown.
    @ObservationIgnored public let isDiagram: Bool
    /// The parser's view of the text: the same bytes as `storage`, read again only around each edit.
    @ObservationIgnored public private(set) var session: LabSession
    /// The page, as the rows a native view draws: made again after each edit.
    public private(set) var document = NativeDocument()
    /// How many edits the text has had.
    public private(set) var revision = 0
    /// What the last edit cost the parser.
    public private(set) var lastEdit: LabEdit?
    /// The text differs from what was last loaded or saved (`markSaved`): by its content, so undoing back to it is not edited.
    public private(set) var isEdited = false
    public var settings: ViewerSettings {
        didSet { if settings != oldValue { refresh() } }
    }

    @ObservationIgnored private var savedLength: Int
    @ObservationIgnored private var savedDigest: Int

    public init(text: String = "", isDiagram: Bool = false, settings: ViewerSettings = ViewerSettings()) {
        storage = NSTextStorage(string: text)
        session = LabSession(text: text)
        self.isDiagram = isDiagram
        self.settings = settings
        savedLength = storage.length
        savedDigest = text.hashValue
        super.init()
        storage.delegate = self
        refresh()
    }

    public var text: String { storage.string }

    /// The text as it is now is what the file holds.
    public func markSaved() {
        savedLength = storage.length
        savedDigest = storage.string.hashValue
        isEdited = false
    }

    /// Takes the text of the file again (it changed on disk, unedited here): the undo history goes, and it counts as saved.
    public func reload(text: String) {
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        undoManager.removeAllActions()
        markSaved()
    }

    /// Does a formatting command on `selection` (UTF-16 units) as one step of undo, and says where the selection goes.
    @discardableResult
    public func perform(_ command: MarkdownCommand, selection: Range<Int>) -> Range<Int> {
        apply(command.edit(in: storage.string, selection: selection))
    }

    /// Makes one replacement, undoable, and says where the selection goes.
    @discardableResult
    public func apply(_ edit: MarkdownEdit) -> Range<Int> {
        let low = min(max(edit.range.lowerBound, 0), storage.length)
        let range = NSRange(location: low, length: min(max(edit.range.upperBound, low), storage.length) - low)
        let inverse = MarkdownEdit(
            range: low ..< (low + edit.replacement.utf16.count),
            replacement: storage.mutableString.substring(with: range),
            selection: low ..< (low + range.length)
        )
        undoManager.registerUndo(withTarget: self) { source in _ = source.apply(inverse) }
        storage.replaceCharacters(in: range, with: edit.replacement)
        return edit.selection
    }

    /// Every change of the characters, whoever made it: the parser replaces the same bytes, and the page is made again.
    /// - Complexity: O(the text up to the edit) to find its bytes, then the parser's own cost for the region.
    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let low = session.utf8Offset(ofUTF16: editedRange.location)
        let high = session.utf8Offset(ofUTF16: editedRange.location + editedRange.length - delta)
        lastEdit = session.replace(low ..< high, with: textStorage.mutableString.substring(with: editedRange))
        revision += 1
        isEdited = textStorage.length != savedLength || textStorage.string.hashValue != savedDigest
        refresh()
    }

    private func refresh() {
        document =
            isDiagram
            ? NativeDocument(diagram: session.text, settings: settings) : session.nativeDocument(settings: settings)
    }
}
