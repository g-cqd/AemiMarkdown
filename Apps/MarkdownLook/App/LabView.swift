import AppKit
import MarkdownLookKit
import SwiftUI

/// The lab (ask roadmap 0204): Markdown on the left, its page on the right, and what each edit cost. The text view reports every change as a range of bytes and the editor of AemiMarkdown
/// re-reads only the blocks around it, so the page follows each keystroke from what the editor holds.
@MainActor @Observable final class LabModel {
    var session: LabSession
    var document = NativeDocument()
    /// A Mermaid file is one diagram, not Markdown.
    @ObservationIgnored let isDiagram: Bool
    var lastEdit: LabEdit?
    var edits = 0
    @ObservationIgnored var settings = ViewerSettings.current()

    init(text: String = LabModel.sample, isDiagram: Bool = false) {
        session = LabSession(text: text)
        self.isDiagram = isDiagram
        refresh()
    }

    func replace(utf16 range: NSRange, with replacement: String) {
        let low = session.utf8Offset(ofUTF16: range.location)
        let high = session.utf8Offset(ofUTF16: range.location + range.length)
        lastEdit = session.replace(low ..< high, with: replacement)
        edits += 1
        refresh()
    }

    func refresh() {
        document =
            isDiagram
            ? NativeDocument(diagram: session.text, settings: settings) : session.nativeDocument(settings: settings)
    }

    /// What the last edit cost, for the toolbar.
    var readout: String {
        guard let edit = lastEdit else { return "\(session.utf8Count) bytes" }
        let micro = Double(edit.nanoseconds) / 1000
        let how = edit.parsedWhole ? "whole document" : "region only"
        return
            "\(edit.blockCount) \(edit.blockCount == 1 ? "block" : "blocks") · \(edit.removedBlocks) out, \(edit.insertedBlocks) in · \(String(format: "%.0f", micro)) µs · \(how)"
    }

    static let sample = """
        # Lab

        Type here: the page follows each edit, and only the blocks around it are read again.

        - a list
        - with [a link](https://example.com)

        ```mermaid
        flowchart LR
          A[Edit] --> B[Parse] --> C[Page]
        ```

        | before | after |
        |:--|--:|
        | whole parse | the region |
        """
}

/// The editor and the page side by side.
struct LabPane: View {
    let model: LabModel
    let settings: ViewerSettings

    var body: some View {
        HSplitView {
            SourceEditor(model: model).frame(minWidth: 280)
            NativeDocumentView(document: model.document, settings: settings).frame(minWidth: 320)
        }
    }
}

/// The lab as a window of its own, on a sample: the same pane the document windows open from their toolbar.
struct LabView: View {
    static let windowID = "lab"
    let store: SettingsStore
    @State private var model = LabModel()

    var body: some View {
        LabPane(model: model, settings: store.settings)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .containerBackground(for: .window) { WindowBackdrop(settings: store.settings) }
            .navigationTitle("Lab")
            .toolbar {
                ToolbarItem(placement: .status) {
                    Text(model.readout).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .onChange(of: store.settings, initial: true) { _, settings in
                model.settings = settings
                model.refresh()
            }
    }
}

struct OpenLabButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Lab") { openWindow(id: LabView.windowID) }.keyboardShortcut("l", modifiers: [.command, .option])
    }
}

/// A plain-text view that tells the model each change before it is made, as a range of the text it holds.
struct SourceEditor: NSViewRepresentable {
    let model: LabModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = Coordinator.font
        view.textContainerInset = NSSize(width: 14, height: 16)
        for flag in [
            \NSTextView.isAutomaticQuoteSubstitutionEnabled, \.isAutomaticDashSubstitutionEnabled,
            \.isAutomaticTextReplacementEnabled, \.isAutomaticSpellingCorrectionEnabled,
            \.isAutomaticLinkDetectionEnabled
        ] {
            view[keyPath: flag] = false
        }
        view.delegate = context.coordinator
        view.string = model.session.text
        context.coordinator.attach(view, in: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let model: LabModel
        private weak var view: NSTextView?
        /// The UTF-16 range last coloured, so scrolling re-colours only when the screen leaves it.
        private var coloured: NSRange?
        private var observer: (any NSObjectProtocol)?

        init(model: LabModel) { self.model = model }

        isolated deinit { observer.map(NotificationCenter.default.removeObserver) }

        /// Colours what is shown, and keeps doing so as the text changes and the view scrolls.
        func attach(_ view: NSTextView, in scroll: NSScrollView) {
            self.view = view
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.scrolled() } }
            highlight()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            model.replace(utf16: range, with: replacementString ?? "")
            return true
        }

        func textDidChange(_ notification: Notification) { highlight() }

        private func scrolled() {
            guard let view, let range = shown(in: view) else { return }
            if let coloured, NSIntersectionRange(coloured, range) == range { return }
            highlight()
        }

        /// The characters on screen, and a screenful more above and below, so a small scroll needs nothing.
        private func shown(in view: NSTextView) -> NSRange? {
            let rect = view.visibleRect
            guard rect.height > 0, view.textStorage != nil else { return nil }
            let top = view.characterIndexForInsertion(at: CGPoint(x: rect.minX, y: rect.minY))
            let bottom = view.characterIndexForInsertion(at: CGPoint(x: rect.maxX, y: rect.maxY))
            guard top != NSNotFound, bottom != NSNotFound, bottom >= top else { return nil }
            return NSRange(location: top, length: bottom - top)
        }

        private func highlight() {
            guard let view, let storage = view.textStorage else { return }
            let rect = view.visibleRect
            // A window of three screens centred on the one shown; the whole text when it is short (the kit decides what is short).
            var window = NSRange(location: 0, length: storage.length)
            if rect.height > 0 {
                let above = CGPoint(x: rect.minX, y: rect.minY - rect.height)
                let below = CGPoint(x: rect.maxX, y: rect.maxY + rect.height)
                let top = Swift.max(view.characterIndexForInsertion(at: above), 0)
                let bottom = Swift.min(view.characterIndexForInsertion(at: below), storage.length)
                if bottom > top { window = NSRange(location: top, length: bottom - top) }
            }
            MarkdownSourceHighlight.apply(to: storage, font: Self.font, visible: window)
            coloured = window
        }
    }
}
