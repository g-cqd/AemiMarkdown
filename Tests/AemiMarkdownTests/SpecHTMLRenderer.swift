@testable import AemiMarkdown

/// Renders a document as the reference HTML of the spec (cmark's `html.c`), from the event walk. It lives in the tests: the library has no opinion about
/// output, so a failing example is a fault in the parser or in this renderer, and the ratchet file records which.
struct SpecHTMLRenderer {
    private var out: [UInt8] = []
    private var stack: [MarkdownNode] = []
    private let document: MarkdownDocument
    private var codeTagOpen = false
    private var link: (destination: [UInt8], title: [UInt8]?)?
    /// Open images, innermost last: each collects the plain text of its description.
    private var images: [(destination: [UInt8], title: [UInt8]?, alt: [UInt8])] = []
    private var imageContainers: [NodeKind] = []
    private var tableBodyOpen = false

    init(_ document: MarkdownDocument) { self.document = document }

    static func html(of document: MarkdownDocument) -> String {
        var renderer = SpecHTMLRenderer(document)
        for event in document.events { renderer.handle(event) }
        return String(decoding: renderer.out, as: UTF8.self)
    }

    private mutating func write(_ text: String) { out.append(contentsOf: Array(text.utf8)) }

    private mutating func carriageReturn() {
        if let last = out.last, last != UInt8(ascii: "\n") { out.append(UInt8(ascii: "\n")) }
    }

    private var parentIsTightList: Bool {
        guard stack.count >= 2, stack[stack.count - 1].kind == .listItem, stack[stack.count - 2].kind == .list else {
            return false
        }
        return ListFlags(rawValue: stack[stack.count - 2].payload).contains(.tight)
    }

    private mutating func handle(_ event: MarkdownEvent) {
        if !images.isEmpty { return handleInImage(event) }
        switch event {
            case .enter(let node): enter(node)
            case .exit(let node): exit(node)
            case .leaf(let node): leaf(node)
        }
    }

    private mutating func openLinkIfNeeded(for event: MarkdownEvent) {
        guard let pending = link else { return }
        if case .leaf(let node) = event, node.kind == .linkDestination || node.kind == .linkTitle { return }
        link = nil
        write("<a href=\"")
        HTMLEscaping.href(pending.destination, into: &out)
        write("\"")
        if let title = pending.title {
            write(" title=\"")
            HTMLEscaping.text(title, into: &out)
            write("\"")
        }
        write(">")
    }

    private mutating func enter(_ node: MarkdownNode) {
        openLinkIfNeeded(for: .enter(node))
        switch node.kind {
            case .paragraph:
                if !parentIsTightList {
                    carriageReturn()
                    write("<p>")
                }
            case .heading:
                carriageReturn()
                write("<h\(node.payload)>")
            case .blockQuote:
                carriageReturn()
                write("<blockquote>\n")
            case .list:
                carriageReturn()
                write(ListFlags(rawValue: node.payload).contains(.ordered) ? "<ol" : "<ul>\n")
            case .listItem:
                carriageReturn()
                write("<li>")
            case .codeBlock:
                carriageReturn()
                write("<pre><code")
                codeTagOpen = true
            case .htmlBlock: carriageReturn()
            case .emphasis: write("<em>")
            case .strong: write("<strong>")
            case .strikethrough: write("<del>")
            case .codeSpan: write("<code>")
            case .link: link = ([], nil)
            case .image:
                images.append(([], nil, []))
                imageContainers = [.image]
            case .table:
                carriageReturn()
                write("<table>\n")
            case .tableRow:
                if node.payload == 1 {
                    write("<thead>\n<tr>\n")
                } else {
                    if !tableBodyOpen { write("<tbody>\n") }
                    tableBodyOpen = true
                    write("<tr>\n")
                }
            case .tableCell:
                let tag = stack.last?.payload == 1 ? "th" : "td"
                let align = ["", " align=\"left\"", " align=\"center\"", " align=\"right\""][node.payload & 3]
                write("<\(tag)\(align)>")
            case .autolink: break
            default: break
        }
        stack.append(node)
    }

    private mutating func exit(_ node: MarkdownNode) {
        openLinkIfNeeded(for: .exit(node))
        stack.removeLast()
        switch node.kind {
            case .paragraph: if !parentIsTightList { write("</p>\n") }
            case .heading: write("</h\(node.payload)>\n")
            case .blockQuote:
                carriageReturn()
                write("</blockquote>\n")
            case .list: write(ListFlags(rawValue: node.payload).contains(.ordered) ? "</ol>\n" : "</ul>\n")
            case .listItem: write("</li>\n")
            case .codeBlock:
                closeCodeTag()
                write("</code></pre>\n")
            case .htmlBlock: carriageReturn()
            case .emphasis: write("</em>")
            case .strong: write("</strong>")
            case .strikethrough: write("</del>")
            case .codeSpan: write("</code>")
            case .link: write("</a>")
            case .autolink: write("</a>")
            case .tableRow: write(node.payload == 1 ? "</tr>\n</thead>\n" : "</tr>\n")
            case .tableCell: write(stack.last?.payload == 1 ? "</th>\n" : "</td>\n")
            case .table:
                if tableBodyOpen { write("</tbody>\n") }
                tableBodyOpen = false
                write("</table>\n")
            default: break
        }
    }

    private mutating func closeCodeTag() {
        guard codeTagOpen else { return }
        codeTagOpen = false
        write(">")
    }

    private mutating func leaf(_ node: MarkdownNode) {
        openLinkIfNeeded(for: .leaf(node))
        let parent = stack.last?.kind
        switch node.kind {
            case .text:
                if parent == .autolink { return writeAutolink(node) }
                HTMLEscaping.text(document.source[node.range], into: &out)
            case .entity: HTMLEscaping.text(document.decode(node.range), into: &out)
            case .htmlInline: out.append(contentsOf: document.source[node.range])
            case .softBreak: write(parent == .codeSpan ? " " : "\n")
            case .hardBreak: write("<br />\n")
            case .thematicBreak:
                carriageReturn()
                write("<hr />\n")
            case .listStart:
                if node.value != 1 { write(" start=\"\(node.value)\"") }
                write(">\n")
            case .infoString:
                let word = document.source[node.range].prefix { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }
                write(" class=\"language-")
                HTMLEscaping.text(
                    document.decode(
                        Range(uncheckedBounds: (node.range.lowerBound, node.range.lowerBound + word.count))), into: &out
                )
                write("\"")
            case .codeLine:
                if parent == .htmlBlock {
                    out.append(contentsOf: document.source[node.range])
                } else {
                    closeCodeTag()
                    HTMLEscaping.text(document.source[node.range], into: &out)
                }
                write("\n")
            case .virtualSpaces:
                closeCodeTag()
                write(String(repeating: " ", count: node.value))
            case .linkDestination: link?.destination = document.decode(node.range)
            case .linkTitle: link?.title = document.decode(node.range)
            default: break
        }
    }

    private mutating func writeAutolink(_ node: MarkdownNode) {
        let kind = stack.last.map { $0.payload } ?? 0
        let text = Array(document.source[node.range])
        write("<a href=\"")
        if kind == 1 { write("mailto:") } else if kind == 2 { write("http://") }
        HTMLEscaping.href(text, into: &out)
        write("\">")
        HTMLEscaping.text(text, into: &out)
    }

    private mutating func handleInImage(_ event: MarkdownEvent) {
        switch event {
            case .enter(let node):
                imageContainers.append(node.kind)
                if node.kind == .image { images.append(([], nil, [])) }
            case .exit(let node):
                imageContainers.removeLast()
                guard node.kind == .image else { return }
                let image = images.removeLast()
                if !images.isEmpty {
                    // Inside another image only the description of this one is text.
                    images[images.count - 1].alt.append(contentsOf: image.alt)
                    return
                }
                var tag: [UInt8] = Array("<img src=\"".utf8)
                HTMLEscaping.href(image.destination, into: &tag)
                tag.append(contentsOf: Array("\" alt=\"".utf8))
                tag.append(contentsOf: image.alt)
                tag.append(UInt8(ascii: "\""))
                if let title = image.title {
                    tag.append(contentsOf: Array(" title=\"".utf8))
                    HTMLEscaping.text(title, into: &tag)
                    tag.append(UInt8(ascii: "\""))
                }
                tag.append(contentsOf: Array(" />".utf8))
                out.append(contentsOf: tag)
            case .leaf(let node):
                let last = images.count - 1
                let ownLeaf = imageContainers.last == .image
                switch node.kind {
                    case .linkDestination where ownLeaf: images[last].destination = document.decode(node.range)
                    case .linkTitle where ownLeaf: images[last].title = document.decode(node.range)
                    case .text, .htmlInline: HTMLEscaping.text(document.source[node.range], into: &images[last].alt)
                    case .entity: HTMLEscaping.text(document.decode(node.range), into: &images[last].alt)
                    case .softBreak, .hardBreak: images[last].alt.append(UInt8(ascii: " "))
                    default: break
                }
        }
    }
}
