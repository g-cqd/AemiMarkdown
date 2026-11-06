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
            .windowResizability(.contentMinSize)
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
            : NativeDocument(MarkdownParser.parse(bytes, extensions: MarkdownLook.extensions), settings: settings)
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
    @AppStorage(Key.bleedsTables, store: .shared) private var bleedsTables = false
    @AppStorage(Key.alignsLeft, store: .shared) private var alignsLeft = false
    @AppStorage(Key.textFont, store: .shared) private var textFont = "system"
    @AppStorage(Key.headingFont, store: .shared) private var headingFont = "text"
    @AppStorage(Key.codeFont, store: .shared) private var codeFont = "mono"
    @AppStorage(Key.diagramFont, store: .shared) private var diagramFont = "text"
    @AppStorage(Key.fontFeatures, store: .shared) private var fontFeatures = ""
    @AppStorage(Key.drawsDiagrams, store: .shared) private var drawsDiagrams = true
    @AppStorage(Key.backdrop, store: .shared) private var backdrop = Backdrop.blurred.rawValue
    @AppStorage(Key.material, store: .shared) private var material = BackdropMaterial.thin.rawValue
    @AppStorage(Key.glass, store: .shared) private var glass = GlassVariant.regular.rawValue

    /// The preset the four fonts add up to, if they are one; choosing one sets them.
    private var typeface: Binding<ViewerFonts.Preset?> {
        Binding {
            ViewerFonts.Preset.allCases.first {
                let fonts = $0.fonts
                return fonts.text.raw == textFont && (fonts.heading?.raw ?? "text") == headingFont
                    && fonts.code.raw == codeFont && (fonts.diagram?.raw ?? "text") == diagramFont
            }
        } set: { preset in
            guard let fonts = preset?.fonts else { return }
            textFont = fonts.text.raw
            headingFont = fonts.heading?.raw ?? "text"
            codeFont = fonts.code.raw
            diagramFont = fonts.diagram?.raw ?? "text"
        }
    }

    var body: some View {
        Form {
            Section("Text") {
                Stepper(value: $textSize, in: ViewerSettings.textSizes) { Text("Text size: \(textSize) pt") }
                Toggle("Text uses the full width of the window", isOn: $fullWidth)
                Toggle("Align the text to the leading edge of the window", isOn: $alignsLeft)
                Toggle("Curly quotes and ellipses", isOn: $smartPunctuation)
            }
            Section {
                Picker("Typeface", selection: typeface) {
                    Text("System").tag(ViewerFonts.Preset.system)
                    Text("Serif").tag(ViewerFonts.Preset.serif)
                    Text("Serif headings, system text").tag(ViewerFonts.Preset.serifDisplay)
                    Text("System headings, serif text").tag(ViewerFonts.Preset.serifText)
                    Text("Custom").tag(ViewerFonts.Preset?.none)
                }
                FontField(title: "Text", value: $textFont, follows: false)
                FontField(title: "Headings", value: $headingFont, follows: true)
                FontField(title: "Code", value: $codeFont, follows: false)
                FontField(title: "Diagrams", value: $diagramFont, follows: true)
                TextField("Features", text: $fontFeatures, prompt: Text("ss01, tnum, cv11=2"))
            } header: {
                Text("Fonts")
            } footer: {
                Text(
                    "A style is set in the system's design (system, serif, rounded, mono) or in the name of an installed family. Features are OpenType tags, applied to all text."
                )
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
                Toggle("Scroll a table across the whole window, from the text's edge", isOn: $bleedsTables)
            }
            Section("Diagrams") {
                Toggle("Draw Mermaid diagrams", isOn: $drawsDiagrams)
            }
            Section {
                Picker("Background", selection: $backdrop) {
                    Text("Solid").tag(Backdrop.solid.rawValue)
                    Text("Material").tag(Backdrop.blurred.rawValue)
                    Text("Glass").tag(Backdrop.glass.rawValue)
                    Text("Clear").tag(Backdrop.clear.rawValue)
                }
                .pickerStyle(.segmented)
                if backdrop == Backdrop.blurred.rawValue {
                    Picker("Material", selection: $material) {
                        Text("Ultra thin").tag(BackdropMaterial.ultraThin.rawValue)
                        Text("Thin").tag(BackdropMaterial.thin.rawValue)
                        Text("Regular").tag(BackdropMaterial.regular.rawValue)
                        Text("Thick").tag(BackdropMaterial.thick.rawValue)
                        Text("Ultra thick").tag(BackdropMaterial.ultraThick.rawValue)
                    }
                }
                if backdrop == Backdrop.glass.rawValue {
                    Picker("Glass", selection: $glass) {
                        Text("Regular").tag(GlassVariant.regular.rawValue)
                        Text("Clear").tag(GlassVariant.clear.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text(
                    "Solid has the most contrast. Quick Look draws its own backdrop behind Material, Glass and Clear. Previews follow all of these choices."
                )
            }
        }
        .formStyle(.grouped)
        // Resizable: a minimum that keeps the controls usable, the size it opens at, and no maximum. A grouped form scrolls when the window is shorter than its content.
        .frame(
            minWidth: 420,
            idealWidth: 460,
            maxWidth: .infinity,
            minHeight: 360,
            idealHeight: 640,
            maxHeight: .infinity
        )
    }
}

/// A document, drawn natively over the backdrop of the settings, with the system's soft scroll edge under the title bar. The toolbar's pencil opens the lab beside it (ask roadmap 0204): the
/// document's own Markdown in an editor on the left, the page on the right following each edit from what the editor of AemiMarkdown holds. The file is not written; the edits are the window's.
struct PageView: View {
    let document: SourceDocument
    let settings: ViewerSettings
    @State private var model: LabModel?
    @State private var editing = false

    var body: some View {
        Group {
            if editing, let model {
                LabPane(model: model, settings: settings)
            } else {
                NativeDocumentView(document: document.native(settings: settings), settings: settings)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .containerBackground(for: .window) { WindowBackdrop(settings: settings) }
        .toolbar {
            if editing, let model {
                ToolbarItem(placement: .status) {
                    Text(model.readout).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $editing) { Label("Edit source", systemImage: "pencil.and.outline") }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .help("Edit the source beside the page (not saved to the file)")
            }
        }
        .onChange(of: editing) { _, on in
            if on, model == nil {
                let lab = LabModel(text: String(decoding: document.bytes, as: UTF8.self), isDiagram: document.isDiagram)
                lab.settings = settings
                lab.refresh()
                model = lab
            }
        }
        .onChange(of: settings) { _, latest in
            model?.settings = latest
            model?.refresh()
        }
    }
}

/// Behind the page: the window's own opaque background, a system material of the chosen thickness, Liquid Glass of the chosen variant, or nothing.
struct WindowBackdrop: View {
    let settings: ViewerSettings

    var body: some View {
        switch settings.backdrop {
            case .solid: Color(nsColor: .windowBackgroundColor)
            case .blurred: Rectangle().fill(material)
            case .glass: Color.clear.glassEffect(settings.glass == .clear ? .clear : .regular, in: .rect)
            case .clear: Color.clear
        }
    }

    private var material: Material {
        switch settings.material {
            case .ultraThin: .ultraThinMaterial
            case .thin: .thinMaterial
            case .regular: .regularMaterial
            case .thick: .thickMaterial
            case .ultraThick: .ultraThickMaterial
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

/// One style's font: a menu of the system's designs and a field for the name of an installed family.
struct FontField: View {
    let title: String
    @Binding var value: String
    /// Whether the style may follow the text's font.
    let follows: Bool

    var body: some View {
        LabeledContent(title) {
            HStack {
                TextField(title, text: $value, prompt: Text("family name")).labelsHidden()
                    .multilineTextAlignment(.trailing)
                Menu {
                    if follows { Button("Same as text") { value = "text" } }
                    Button("System") { value = "system" }
                    Button("Serif") { value = "serif" }
                    Button("Rounded") { value = "rounded" }
                    Button("Monospaced") { value = "mono" }
                } label: {
                    Image(systemName: "textformat")
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }
}
