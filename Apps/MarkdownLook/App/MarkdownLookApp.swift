import AemiMarkdown
import AppKit
import MarkdownLookKit
import SwiftUI
import UniformTypeIdentifiers

/// The app that carries the Quick Look extensions (roadmap 0201) and shows a Markdown or Mermaid file in a window with the same renderer. The extensions are registered with the system
/// when the app is first run from /Applications or ~/Applications. Every behaviour the viewer assumes is a choice in the Settings window, and Quick Look follows the same choices.
@main
struct MarkdownLookApp: App {
    @State private var store = SettingsStore()

    var body: some Scene {
        DocumentGroup(viewing: SourceDocument.self) { file in
            PageView(
                document: file.document,
                settings: store.settings
            )
            .ignoresSafeArea()
            .background(TitlebarSeparator())
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SettingsLink { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            }
        }
        Window("Lab", id: LabView.windowID) { LabView(store: store) }
            .defaultSize(width: 1200, height: 760)
        Settings { SettingsView() }
            .commands { CommandGroup(after: .newItem) { OpenLabButton() } }
    }
}

extension UserDefaults {
    /// The domain the preview extension reads.
    nonisolated(unsafe) static let shared = UserDefaults(suiteName: ViewerSettings.domain) ?? .standard
}

/// The settings as the windows read them, current whenever a choice is made in the Settings window (or by `defaults`).
@MainActor @Observable final class SettingsStore {
    var settings = ViewerSettings.current()
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func reload() {
        let latest = ViewerSettings.current()
        if latest != settings { settings = latest }
    }
}

struct SourceDocument: FileDocument {
    static let readableContentTypes: [UTType] = [
        UTType("net.daringfireball.markdown") ?? .plainText, UTType("studio.aemi.mermaid") ?? .plainText, .plainText
    ]
    let bytes: [UInt8]
    let isDiagram: Bool

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        bytes = Array(data)
        let name = configuration.file.filename?.lowercased() ?? ""
        isDiagram = name.hasSuffix(".mmd") || name.hasSuffix(".mermaid")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { throw CocoaError(.featureUnsupported) }

    /// The document as the rows the app draws.
    func native(settings: ViewerSettings) -> NativeDocument {
        isDiagram
            ? NativeDocument(diagram: String(decoding: bytes, as: UTF8.self), settings: settings)
            : NativeDocument(MarkdownParser.parse(bytes), settings: settings)
    }
}

/// Every choice of the viewer, in the app's own preferences domain (which is where the preview extension reads them).
struct SettingsView: View {
    private typealias Key = ViewerSettings.Key
    @AppStorage(Key.textSize, store: .shared) private var textSize = ViewerSettings.defaultTextSize
    @AppStorage(Key.fullWidth, store: .shared) private var fullWidth = false
    @AppStorage(Key.smartPunctuation, store: .shared) private var smartPunctuation = true
    @AppStorage(Key.highlightsCode, store: .shared) private var highlightsCode = true
    @AppStorage(Key.showsLanguage, store: .shared) private var showsLanguage = true
    @AppStorage(Key.copyButton, store: .shared) private var copyButton = true
    @AppStorage(Key.tabSize, store: .shared) private var tabSize = ViewerSettings.defaultTabSize
    @AppStorage(Key.rowLines, store: .shared) private var rowLines = true
    @AppStorage(Key.columnLines, store: .shared) private var columnLines = false
    @AppStorage(Key.outerBorder, store: .shared) private var outerBorder = false
    @AppStorage(Key.scrollsTables, store: .shared) private var scrollsTables = false
    @AppStorage(Key.drawsDiagrams, store: .shared) private var drawsDiagrams = true
    @AppStorage(Key.backdrop, store: .shared) private var backdrop = Backdrop.blurred.rawValue

    var body: some View {
        Form {
            Section("Text") {
                Stepper(value: $textSize, in: ViewerSettings.textSizes) { Text("Text size: \(textSize) pt") }
                Toggle("Text uses the full width of the window", isOn: $fullWidth)
                Toggle("Curly quotes and ellipses", isOn: $smartPunctuation)
            }
            Section("Code") {
                Toggle("Syntax colour", isOn: $highlightsCode)
                Toggle("Show the language of a block", isOn: $showsLanguage)
                Toggle("Copy button on code blocks", isOn: $copyButton)
                Stepper(value: $tabSize, in: ViewerSettings.tabSizes) {
                    Text("A tab is \(tabSize) \(tabSize == 1 ? "space" : "spaces") wide")
                }
            }
            Section("Tables") {
                Toggle("Lines between rows", isOn: $rowLines)
                Toggle("Lines between columns", isOn: $columnLines)
                Toggle("Outline around the table", isOn: $outerBorder)
                Toggle("Keep cells on one line and scroll wide tables", isOn: $scrollsTables)
            }
            Section("Diagrams") {
                Toggle("Draw Mermaid diagrams", isOn: $drawsDiagrams)
            }
            Section {
                Picker("Background", selection: $backdrop) {
                    Text("Solid").tag(Backdrop.solid.rawValue)
                    Text("Blurred").tag(Backdrop.blurred.rawValue)
                    Text("Clear").tag(Backdrop.clear.rawValue)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(
                    "Solid has the most contrast. Quick Look draws its own backdrop behind Blurred and Clear. Previews follow all of these choices."
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A document, drawn natively over the backdrop of the settings, with the system's soft scroll edge under the title bar.
struct PageView: View {
    let document: SourceDocument
    let settings: ViewerSettings

    var body: some View {
        NativeDocumentView(document: document.native(settings: settings), settings: settings)
            .containerBackground(for: .window) { WindowBackdrop(mode: settings.backdrop) }
    }
}

/// Behind the page: the window's own opaque background, the system's blurred material, or nothing.
struct WindowBackdrop: View {
    let mode: Backdrop

    var body: some View {
        switch mode {
            case .solid: Color(nsColor: .windowBackgroundColor)
            case .blurred: Rectangle().fill(.thinMaterial)
            case .clear: Color.clear
        }
    }
}

/// The window's title bar without its hairline: the page scrolls under the toolbar and the system's soft edge fades it, which a line across the window would undo.
struct TitlebarSeparator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Probe)?.apply() }

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            window?.titlebarSeparatorStyle = .none
            DispatchQueue.main.async { [weak self] in self?.window?.titlebarSeparatorStyle = .none }
        }
    }
}
