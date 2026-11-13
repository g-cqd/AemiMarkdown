public import AppKit

/// What one editor does besides showing the text (ADR-0008): it gives its text view the source's undo history, colours the
/// Markdown that is on screen and keeps doing so as the text changes and the view scrolls, and does commands on its selection.
@available(macOS 26.0, *)
@MainActor
public final class MarkdownSourceEditorCoordinator: NSObject, NSTextViewDelegate {
    let source: MarkdownSource
    private var configuration: MarkdownEditorConfiguration
    private weak var view: NSTextView?
    private weak var proxy: MarkdownEditorProxy?
    /// The UTF-16 range last coloured, so scrolling colours again only when the screen leaves it.
    private var coloured: NSRange?
    private var observer: (any NSObjectProtocol)?

    init(source: MarkdownSource, configuration: MarkdownEditorConfiguration) {
        self.source = source
        self.configuration = configuration
    }

    isolated deinit { observer.map(NotificationCenter.default.removeObserver) }

    private var font: NSFont { .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular) }

    func attach(_ view: NSTextView, in scroll: NSScrollView, proxy: MarkdownEditorProxy?) {
        self.view = view
        scroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.scrolled() } }
        update(configuration, proxy: proxy)
        highlight()
    }

    func update(_ next: MarkdownEditorConfiguration, proxy: MarkdownEditorProxy?) {
        if self.proxy !== proxy {
            self.proxy?.coordinator = nil
            self.proxy = proxy
            proxy?.coordinator = self
            proxy?.selection = view.map { Range($0.selectedRange()) } ?? nil
        }
        guard next != configuration else { return }
        configuration = next
        view?.font = font
        view?.textContainerInset = next.inset
        highlight()
    }

    func detach() {
        proxy?.coordinator = nil
        proxy?.selection = nil
        if let view { MarkdownSourceEditor.detach(view, from: source) }
    }

    func perform(_ command: MarkdownCommand) {
        guard let view, let selection = Range(view.selectedRange()) else { return }
        let next = source.perform(command, selection: selection)
        view.setSelectedRange(NSRange(next))
        view.scrollRangeToVisible(NSRange(next))
    }

    func focus() {
        guard let view else { return }
        // AppKit declares a view's window unowned(unsafe); a view in a window is kept by it.
        unsafe view.window?.makeFirstResponder(view)
    }

    // MARK: NSTextViewDelegate

    public func undoManager(for view: NSTextView) -> UndoManager? { source.undoManager }

    public func textDidChange(_ notification: Notification) { highlight() }

    public func textViewDidChangeSelection(_ notification: Notification) {
        proxy?.selection = view.map { Range($0.selectedRange()) } ?? nil
    }

    // MARK: Colour

    private func scrolled() {
        guard let view, let range = shown(in: view) else { return }
        if let coloured, NSIntersectionRange(coloured, range) == range { return }
        highlight()
    }

    /// The characters on screen.
    private func shown(in view: NSTextView) -> NSRange? {
        let rect = view.visibleRect
        guard rect.height > 0 else { return nil }
        let top = view.characterIndexForInsertion(at: CGPoint(x: rect.minX, y: rect.minY))
        let bottom = view.characterIndexForInsertion(at: CGPoint(x: rect.maxX, y: rect.maxY))
        guard top != NSNotFound, bottom != NSNotFound, bottom >= top else { return nil }
        return NSRange(location: top, length: bottom - top)
    }

    /// Colours three screens centred on the one shown; the whole text when it is short (the styler decides what is short). Only
    /// that window of the shared storage is touched, so another editor of the same text keeps the colours of what it shows.
    private func highlight() {
        guard let view else { return }
        let storage = source.storage
        let rect = view.visibleRect
        var window = NSRange(location: 0, length: storage.length)
        if rect.height > 0 {
            let above = CGPoint(x: rect.minX, y: rect.minY - rect.height)
            let below = CGPoint(x: rect.maxX, y: rect.maxY + rect.height)
            let top = Swift.max(view.characterIndexForInsertion(at: above), 0)
            let bottom = Swift.min(view.characterIndexForInsertion(at: below), storage.length)
            if bottom > top { window = NSRange(location: top, length: bottom - top) }
        }
        MarkdownSourceHighlight.apply(to: storage, font: font, visible: window)
        coloured = window
    }
}
