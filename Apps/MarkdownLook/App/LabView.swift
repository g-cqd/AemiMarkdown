import AppKit
import MarkdownLookKit
import SwiftUI

/// The lab (ask roadmap 0204): Markdown on the left, its page on the right, and what each edit cost. The text view reports every change as a range of bytes and the editor of AemiMarkdown
/// re-reads only the blocks around it, so the page follows each keystroke from what the editor holds.
@MainActor @Observable final class LabModel {
    var session = LabSession(text: LabModel.sample)
    var html = ""
    var lastEdit: LabEdit?
    var edits = 0
    @ObservationIgnored var settings = ViewerSettings.current()

    init() { refresh() }

    func replace(utf16 range: NSRange, with replacement: String) {
        let low = session.utf8Offset(ofUTF16: range.location)
        let high = session.utf8Offset(ofUTF16: range.location + range.length)
        lastEdit = session.replace(low ..< high, with: replacement)
        edits += 1
        refresh()
    }

    func refresh() { html = session.page(title: "Lab", settings: settings) }

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

struct LabView: View {
    static let windowID = "lab"
    let store: SettingsStore
    @State private var model = LabModel()

    var body: some View {
        HSplitView {
            SourceEditor(model: model).frame(minWidth: 280)
            HTMLPageView(html: model.html).frame(minWidth: 320)
        }
        .containerBackground(for: .window) { WindowBackdrop(mode: store.settings.backdrop) }
        .navigationTitle("Lab")
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(readout).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .onChange(of: store.settings, initial: true) { _, settings in
            model.settings = settings
            model.refresh()
        }
    }

    private var readout: String {
        guard let edit = model.lastEdit else { return "\(model.session.utf8Count) bytes" }
        let micro = Double(edit.nanoseconds) / 1000
        let how = edit.parsedWhole ? "whole document" : "region only"
        return
            "\(edit.blockCount) blocks · \(edit.removedBlocks) out, \(edit.insertedBlocks) in · \(String(format: "%.0f", micro)) µs · \(how)"
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
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
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
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let model: LabModel

        init(model: LabModel) { self.model = model }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            model.replace(utf16: range, with: replacementString ?? "")
            return true
        }
    }
}
