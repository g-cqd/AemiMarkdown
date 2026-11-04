import MarkdownLookKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The app that carries the Quick Look extensions (roadmap 0201) and shows a Markdown or Mermaid file in a window with the same renderer: the extensions are registered with the system
/// when the app is first run from /Applications or ~/Applications.
@main
struct MarkdownLookApp: App {
    var body: some Scene {
        DocumentGroup(viewing: SourceDocument.self) { file in
            PageView(html: file.document.page(title: file.fileURL?.lastPathComponent ?? "Untitled"))
        }
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

    func page(title: String) -> String {
        isDiagram
            ? MarkdownHTMLRenderer().diagramPage(bytes, title: title)
            : MarkdownHTMLRenderer().page(markdown: bytes, title: title)
    }
}

struct PageView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ view: WKWebView, context: Context) { view.loadHTMLString(html, baseURL: nil) }
}
