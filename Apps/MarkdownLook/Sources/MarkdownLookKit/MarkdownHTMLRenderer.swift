public import AemiMarkdown
internal import AemiMermaidSVG

/// A Markdown document as HTML for a viewer (ADR 0007): the structure a reader sees, with nothing in it the document could have used to act. Raw HTML in the document is shown as text,
/// a link with a scheme other than `http`, `https` and `mailto` is not a link, an image is not loaded (the page has no network in Quick Look), and a mermaid fence is an inline SVG.
///
/// ```swift
/// let document = MarkdownParser.parse(Array("# Title\n\n```mermaid\nflowchart TD\n  A --> B\n```\n".utf8))
/// let page = MarkdownHTMLRenderer().page(document, title: "Title")
/// ```
public struct MarkdownHTMLRenderer: Sendable {
    /// Curly quotes and ellipses in prose (not in code).
    public var smartPunctuation = true
    /// Draw `mermaid` fences as diagrams.
    public var drawsDiagrams = true

    public init() {}

    /// The document's content as HTML, with no page around it. `embedsDiagramStyle` puts the diagrams' style sheet in each SVG; a page that carries it once turns it off.
    public func body(_ document: MarkdownDocument, embedsDiagramStyle: Bool = true) -> String {
        var writer = HTMLWriter(document: document, options: self, embedsDiagramStyle: embedsDiagramStyle)
        for event in document.events { writer.handle(event) }
        return writer.finish()
    }

    /// A whole HTML page for `document`: the viewer's style sheet, the diagrams' once, and the content in a column of readable width.
    public func page(_ document: MarkdownDocument, title: String) -> String {
        wrap(body(document, embedsDiagramStyle: false), title: title)
    }

    /// A whole page for the bytes of a Markdown file.
    public func page(markdown bytes: [UInt8], title: String) -> String {
        page(MarkdownParser.parse(bytes), title: title)
    }

    /// A page for a Mermaid file: the diagram alone, or its source as code when the engine does not draw it.
    public func diagramPage(_ source: [UInt8], title: String) -> String {
        let content: String
        if drawsDiagrams, let svg = MermaidFence.svg(source, embedsStyle: false) {
            content = "<figure>" + svg + "</figure>\n"
        } else {
            content = "<pre><code>" + HTMLText.escaped(String(decoding: source, as: UTF8.self)) + "</code></pre>\n"
        }
        return wrap(content, title: title)
    }

    private func wrap(_ content: String, title: String) -> String {
        "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<title>\(HTMLText.escaped(title))</title><style>\(ViewerStyle.sheet)\n\(SVGStyle.sheet)</style></head><body><main>\n\(content)</main></body></html>\n"
    }
}
