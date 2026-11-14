public import AppKit
public import Observation

/// The one text behind every view of a document (ADR-0008): a text storage that any number of editors show and edit, the undo
/// history they share, the parser's session kept in step with each edit wherever it comes from (a key typed in any editor, a
/// command, undo), and the page made from what the parser holds. Whoever owns a document owns one of these per file; panes are
/// views of it, so two of them can never hold two versions of the text.
///
/// The page is made when it is asked for, and kept until the text or the settings change (ADR-0009): a text that only editors
/// show makes none. Plain text (`Content.plain`) is held and edited without the parser at all.
@available(macOS 26.0, *)
@MainActor @Observable
public final class MarkdownSource: NSObject, @MainActor NSTextStorageDelegate {
    /// The text as the editors hold it. Change it through an editor, `perform` or `apply`; any change is followed.
    @ObservationIgnored public let storage: NSTextStorage
    /// One history for every editor of this text.
    @ObservationIgnored public let undoManager = UndoManager()
    /// What the text is read as.
    @ObservationIgnored public let content: Content
    /// The parser's view of the text: the same bytes as `storage`, read again only around each edit. Empty for plain text.
    @ObservationIgnored public private(set) var session: LabSession
    /// How many times the page was made: what an edit costs when something shows the page, and nothing when nothing does.
    @ObservationIgnored public private(set) var pagesMade = 0
    /// The page as it was last made, while the text and the settings it was made from stand.
    @ObservationIgnored private var page: NativeDocument?
    /// How many edits the text has had.
    public private(set) var revision = 0
    /// What the last edit cost the parser.
    public private(set) var lastEdit: LabEdit?
    /// The text differs from what was last loaded or saved (`markSaved`): by its content, so undoing back to it is not edited.
    public private(set) var isEdited = false
    public var settings: ViewerSettings {
        didSet { if settings != oldValue { page = nil } }
    }

    @ObservationIgnored private var savedLength: Int
    @ObservationIgnored private var savedDigest: Int

    public init(text: String = "", content: Content, settings: ViewerSettings = ViewerSettings()) {
        storage = NSTextStorage(string: text)
        session = LabSession(text: content == .plain ? "" : text)
        self.content = content
        self.settings = settings
        savedLength = storage.length
        savedDigest = Self.digest(storage.mutableString)
        super.init()
        storage.delegate = self
    }

    public convenience init(text: String = "", isDiagram: Bool = false, settings: ViewerSettings = ViewerSettings()) {
        self.init(text: text, content: isDiagram ? .diagram : .markdown, settings: settings)
    }

    public var text: String { storage.string }
    /// A Mermaid file is one diagram, not Markdown.
    public var isDiagram: Bool { content == .diagram }

    /// The page, as the rows a native view draws: made when asked for, once for each state of the text and the settings.
    /// Whoever reads it is told of the next change. Plain text has none.
    /// - Complexity: O(the document) when the text or the settings changed since it was last asked for, O(1) otherwise.
    public var document: NativeDocument {
        // Read so that an observer of the page is told of the next edit and the next change of settings.
        _ = revision
        let settings = settings
        if let page { return page }
        let made: NativeDocument
        switch content {
            case .markdown: made = session.nativeDocument(settings: settings)
            case .diagram: made = NativeDocument(diagram: session.text, settings: settings)
            case .plain: return NativeDocument()
        }
        pagesMade += 1
        page = made
        return made
    }

    /// The text as it is now is what the file holds.
    public func markSaved() {
        savedLength = storage.length
        savedDigest = Self.digest(storage.mutableString)
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

    /// Every change of the characters, whoever made it: the parser replaces the same bytes, and the page is to be made again.
    /// - Complexity: O(the text up to the edit) to find its bytes, then the parser's own cost for the region; nothing of the
    ///   page. Plain text: O(1), unless the text is again as long as what was saved (then its digest, O(the text)).
    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        if content != .plain {
            let low = session.utf8Offset(ofUTF16: editedRange.location)
            let high = session.utf8Offset(ofUTF16: editedRange.location + editedRange.length - delta)
            lastEdit = session.replace(low ..< high, with: textStorage.mutableString.substring(with: editedRange))
        }
        page = nil
        revision += 1
        isEdited = textStorage.length != savedLength || Self.digest(textStorage.mutableString) != savedDigest
    }

    /// A digest of the text's UTF-16 units, read in pieces: no copy of the text is made, and none is kept. (A `String` made
    /// from the storage hashes some forty times slower: measured at 78 ms for 2 MB, which every save paid.)
    /// - Complexity: O(the text).
    private static func digest(_ text: NSString) -> Int {
        var hasher = Hasher()
        var piece = [unichar](repeating: 0, count: 8192)
        let length = text.length
        var location = 0
        while location < length {
            let count = min(piece.count, length - location)
            piece.withUnsafeMutableBufferPointer { units in
                guard let base = units.baseAddress else { return }
                unsafe text.getCharacters(base, range: NSRange(location: location, length: count))
                unsafe hasher.combine(
                    bytes: UnsafeRawBufferPointer(start: base, count: count * MemoryLayout<unichar>.size)
                )
            }
            location += count
        }
        return hasher.finalize()
    }
}
