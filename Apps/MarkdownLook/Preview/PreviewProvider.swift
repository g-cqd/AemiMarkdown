import Foundation
import MarkdownLookKit
import QuickLookUI
import UniformTypeIdentifiers

/// The Quick Look preview for Markdown and Mermaid files: an HTML reply made by `MarkdownLookKit`, with diagrams as inline SVG (ADR 0004). The reply needs no network and no script.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    /// The largest file read whole; beyond it the preview shows the start and says so.
    private static let limit = 8 << 20

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let handle = try FileHandle(forReadingFrom: request.fileURL)
        defer { try? handle.close() }
        let bytes = Array(try handle.read(upToCount: Self.limit) ?? Data())
        let title = request.fileURL.lastPathComponent
        let name = title.lowercased()
        let isDiagram = name.hasSuffix(".mmd") || name.hasSuffix(".mermaid")
        var renderer = MarkdownHTMLRenderer()
        renderer.settings = ViewerSettings.current()
        let page = isDiagram ? renderer.diagramPage(bytes, title: title) : renderer.page(markdown: bytes, title: title)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 800)) { reply in
            reply.stringEncoding = .utf8
            return Data(page.utf8)
        }
        reply.title = title
        return reply
    }
}
