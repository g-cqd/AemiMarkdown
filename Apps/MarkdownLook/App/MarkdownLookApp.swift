import AppKit
import MarkdownLookKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The app that carries the Quick Look extensions (roadmap 0201) and shows a Markdown or Mermaid file in a window with the same renderer. The extensions are registered with the system
/// when the app is first run from /Applications or ~/Applications. Settings (width of the text, width of a tab) are in the Settings window and apply to the windows and to Quick Look.
@main
struct MarkdownLookApp: App {
    var body: some Scene {
        DocumentGroup(viewing: SourceDocument.self) { file in
            PageView(document: file.document, title: file.fileURL?.lastPathComponent ?? "Untitled")
        }
        Settings { SettingsView() }
    }
}

extension UserDefaults {
    /// The domain the preview extension reads.
    nonisolated(unsafe) static let shared = UserDefaults(suiteName: ViewerSettings.domain) ?? .standard
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
        var renderer = MarkdownHTMLRenderer()
        renderer.settings = settings
        return isDiagram ? renderer.diagramPage(bytes, title: title) : renderer.page(markdown: bytes, title: title)
    }
}

/// The choices of the Settings window, in the app's own preferences domain (which is where the preview extension reads them).
struct SettingsView: View {
    @AppStorage(ViewerSettings.fullWidthKey, store: .shared) private var fullWidth = false
    @AppStorage(ViewerSettings.tabSizeKey, store: .shared) private var tabSize = ViewerSettings.defaultTabSize

    var body: some View {
        Form {
            Toggle("Text uses the full width of the window", isOn: $fullWidth)
            Stepper(value: $tabSize, in: ViewerSettings.tabSizes) {
                Text("A tab in code is \(tabSize) \(tabSize == 1 ? "space" : "spaces") wide")
            }
            Text("Quick Look previews follow these choices too.").font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PageView: NSViewRepresentable {
    let document: SourceDocument
    let title: String
    @AppStorage(ViewerSettings.fullWidthKey, store: .shared) private var fullWidth = false
    @AppStorage(ViewerSettings.tabSizeKey, store: .shared) private var tabSize = ViewerSettings.defaultTabSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let html = document.page(title: title, settings: ViewerSettings(fullWidth: fullWidth, tabSize: tabSize))
        guard html != context.coordinator.loaded else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: nil)
    }

    /// The page is loaded once; a link a reader follows opens in the browser, never in the window.
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
