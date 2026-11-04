import AppKit
import MarkdownLookKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The app that carries the Quick Look extensions (roadmap 0201) and shows a Markdown or Mermaid file in a window with the same renderer. The extensions are registered with the system
/// when the app is first run from /Applications or ~/Applications. Every behaviour the viewer assumes is a choice in the Settings window, and Quick Look follows the same choices.
@main
struct MarkdownLookApp: App {
    @State private var store = SettingsStore()

    var body: some Scene {
        DocumentGroup(viewing: SourceDocument.self) { file in
            PageView(
                document: file.document,
                title: file.fileURL?.lastPathComponent ?? "Untitled",
                settings: store.settings
            )
            .ignoresSafeArea()
            .scrollEdgeEffectStyle(.soft, for: .top)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SettingsLink { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            }
        }
        Settings { SettingsView() }
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

    func page(title: String, settings: ViewerSettings) -> String {
        let renderer = MarkdownHTMLRenderer(settings: settings)
        return isDiagram ? renderer.diagramPage(bytes, title: title) : renderer.page(markdown: bytes, title: title)
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

/// The page, over the backdrop the setting asks for: the window's own opaque background, the system's blurred material, or nothing.
struct PageView: NSViewRepresentable {
    let document: SourceDocument
    let title: String
    let settings: ViewerSettings

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PageContainer {
        let container = PageContainer()
        container.web.navigationDelegate = context.coordinator
        return container
    }

    func updateNSView(_ container: PageContainer, context: Context) {
        container.apply(settings.backdrop)
        let html = document.page(title: title, settings: settings)
        guard html != context.coordinator.loaded else { return }
        context.coordinator.loaded = html
        container.web.loadHTMLString(html, baseURL: nil)
    }

    /// The page is loaded once per change; a link a reader follows opens in the browser, never in the window.
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded = ""

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy
        {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            return .cancel
        }
    }
}

/// The material behind a transparent web view, and the window made to let it show.
final class PageContainer: NSView {
    let web: WKWebView
    private let material = NSVisualEffectView()
    private var backdrop = Backdrop.blurred

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        material.material = .underWindowBackground
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        for view in [material, web] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        web.setValue(false, forKey: "drawsBackground")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not from a nib") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply(backdrop)
    }

    func apply(_ backdrop: Backdrop) {
        self.backdrop = backdrop
        material.isHidden = backdrop != .blurred
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isOpaque = backdrop == .solid
        window.backgroundColor = backdrop == .solid ? .windowBackgroundColor : .clear
    }
}
