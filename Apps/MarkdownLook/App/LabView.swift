import AppKit
import MarkdownLookKit
import SwiftUI

/// The lab (ask roadmap 0204): Markdown on the left, its page on the right, and what each edit cost. The text is a `MarkdownSource` of the kit (ADR-0008): the editor shows its storage, every
/// change is read by the parser's session as a replacement of bytes around the edit, and the page follows from what the session holds.
enum Lab {
    /// What the last edit cost, for the toolbar.
    @MainActor
    static func readout(of source: MarkdownSource) -> String {
        guard let edit = source.lastEdit else { return "\(source.session.utf8Count) bytes" }
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
    let source: MarkdownSource
    let settings: ViewerSettings

    var body: some View {
        HSplitView {
            MarkdownSourceEditor(source: source).frame(minWidth: 280)
            NativeDocumentView(document: source.document, settings: settings).frame(minWidth: 320)
        }
    }
}

/// The lab as a window of its own, on a sample: the same pane the document windows open from their toolbar.
struct LabView: View {
    static let windowID = "lab"
    let store: SettingsStore
    @State private var source = MarkdownSource(text: Lab.sample)

    var body: some View {
        LabPane(source: source, settings: store.settings)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .containerBackground(for: .window) { WindowBackdrop(settings: store.settings) }
            .navigationTitle("Lab")
            .toolbar {
                ToolbarItem(placement: .status) {
                    Text(Lab.readout(of: source)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .onChange(of: store.settings, initial: true) { _, settings in source.settings = settings }
    }
}

struct OpenLabButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Lab") { openWindow(id: LabView.windowID) }.keyboardShortcut("l", modifiers: [.command, .option])
    }
}
