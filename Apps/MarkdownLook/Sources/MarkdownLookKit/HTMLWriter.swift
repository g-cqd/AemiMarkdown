internal import AemiMarkdown

/// Walks a document's events once and writes HTML: the open blocks on an explicit stack, an element's start tag held open while the leaves that give it attributes arrive (a list's
/// start number, a link's destination and title). No recursion.
struct HTMLWriter {
    /// A block or inline element that is open.
    struct Frame {
        var kind: NodeKind
        /// A list that is tight (and the items in it): its paragraphs are not wrapped.
        var tight = false
        var closing = ""
    }

    let document: MarkdownDocument
    let options: MarkdownHTMLRenderer
    let embedsDiagramStyle: Bool
    var out = ""
    var stack: [Frame] = []
    /// Whether a start tag is still open (no `>` yet), because attributes may follow.
    var headOpen = false
    var smart = SmartPunctuation()
    var codeDepth = 0
    var codeLines: [String] = []
    var language = ""
    var inCode = false
    var tableBody = false
    var headerRow = false
    var cellTag = "td"
    /// The kind of the autolink being written (the payload of its node), or nil outside one.
    var autolinkKind: Int?
    var pendingSpaces = 0

    init(document: MarkdownDocument, options: MarkdownHTMLRenderer, embedsDiagramStyle: Bool) {
        self.document = document
        self.options = options
        self.embedsDiagramStyle = embedsDiagramStyle
        out.reserveCapacity(document.source.count * 2)
    }

    mutating func finish() -> String {
        closeHead()
        while let frame = stack.popLast() { out += frame.closing }
        return out
    }

    mutating func closeHead() {
        if headOpen {
            out += ">"
            headOpen = false
        }
    }

    func text(_ range: Range<Int>) -> String { String(decoding: document.source[range], as: UTF8.self) }

    mutating func handle(_ event: MarkdownEvent) {
        if case .leaf(let node) = event, [.listStart, .linkDestination, .linkTitle].contains(node.kind) {
            attribute(node)
            return
        }
        closeHead()
        switch event {
            case .enter(let node): enter(node)
            case .exit(let node): exit(node)
            case .leaf(let node): leaf(node)
        }
    }

    /// Whether the innermost open block is a tight list's item: its paragraphs are bare.
    private var inTightItem: Bool { stack.last?.kind == .listItem && stack.last?.tight == true }

    private mutating func open(
        _ node: NodeKind,
        _ tag: String,
        attributes: String = "",
        closing: String? = nil,
        tight: Bool = false,
        headOpen keep: Bool = false
    ) {
        out += "<" + tag + attributes
        if keep { headOpen = true } else { out += ">" }
        stack.append(Frame(kind: node, tight: tight, closing: closing ?? "</\(tag)>"))
    }

    mutating func enter(_ node: MarkdownNode) {
        switch node.kind {
            case .paragraph:
                smart = SmartPunctuation()
                if inTightItem { stack.append(Frame(kind: .paragraph, closing: "\n")) } else { open(.paragraph, "p") }
            case .heading:
                smart = SmartPunctuation()
                open(.heading, "h\(Swift.min(6, Swift.max(1, node.payload)))")
            case .blockQuote:
                if (1 ... 5).contains(node.payload) {
                    let kind = ["note", "tip", "important", "warning", "caution"][node.payload - 1]
                    out +=
                        "<div class=\"alert \(kind)\"><p class=\"alert-title\">\(kind.prefix(1).uppercased() + kind.dropFirst())</p>\n"
                    stack.append(Frame(kind: .blockQuote, closing: "</div>\n"))
                } else {
                    open(.blockQuote, "blockquote")
                    out += "\n"
                }
            case .list:
                let flags = ListFlags(rawValue: node.payload)
                let tag = flags.contains(.ordered) ? "ol" : "ul"
                open(
                    .list,
                    tag,
                    attributes: flags.contains(.tight) ? " class=\"tight\"" : "",
                    tight: flags.contains(.tight),
                    headOpen: flags.contains(.ordered)
                )
            case .listItem:
                open(.listItem, "li", tight: stack.last?.tight == true)
            case .codeBlock, .htmlBlock:
                inCode = true
                codeLines = []
                language = ""
                stack.append(Frame(kind: node.kind, closing: ""))
            case .table:
                tableBody = false
                open(.table, "table", closing: "</table>\n")
                out += "\n"
            case .tableRow:
                headerRow = node.payload == 1
                if headerRow {
                    out += "<thead>"
                } else if !tableBody {
                    tableBody = true
                    out += "<tbody>"
                }
                open(.tableRow, "tr", closing: headerRow ? "</tr></thead>" : "</tr>")
            case .tableCell:
                smart = SmartPunctuation()
                let tag = headerRow ? "th" : "td"
                let alignment = [1: "", 2: " class=\"c\"", 3: " class=\"r\""][node.payload] ?? ""
                open(.tableCell, tag, attributes: alignment)
            case .footnoteDefinition: open(.footnoteDefinition, "div", attributes: " class=\"footnote\"")
            case .emphasis: open(.emphasis, "em")
            case .strong: open(.strong, "strong")
            case .strikethrough: open(.strikethrough, "del")
            case .codeSpan, .math:
                codeDepth += 1
                open(node.kind, "code", attributes: node.kind == .math ? " class=\"math\"" : "")
            case .link: open(.link, "a", closing: "</a>", headOpen: true)
            case .image: open(.image, "span", attributes: " class=\"image\"", closing: "</span>", headOpen: true)
            case .autolink: autolinkKind = node.payload
            default: break
        }
    }

    mutating func exit(_ node: MarkdownNode) {
        switch node.kind {
            case .codeBlock, .htmlBlock: finishCode(isHTML: node.kind == .htmlBlock)
            case .autolink: autolinkKind = nil
            case .table:
                if tableBody { out += "</tbody>" }
                closeFrame()
            case .codeSpan, .math:
                codeDepth -= 1
                closeFrame()
            case .listItem, .list, .blockQuote, .footnoteDefinition, .tableRow, .tableCell, .heading, .paragraph:
                closeFrame()
                if [.listItem, .blockQuote, .tableRow, .tableCell, .heading].contains(node.kind) { out += "\n" }
            default: closeFrame()
        }
    }

    private mutating func closeFrame() {
        if let frame = stack.popLast() { out += frame.closing }
    }
}
