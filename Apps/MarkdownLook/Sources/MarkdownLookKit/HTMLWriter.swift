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
    /// The info word as the document wrote it, to find the language by; `language` is the same, escaped, for the class.
    var rawLanguage = ""
    var inCode = false
    var tableBody = false
    var headerRow = false
    var cellTag = "td"
    /// The text written before the table in progress, and the table's measurements; the table is written on its own so its columns can be sized when it ends.
    var beforeTable = ""
    var tableLayout = TableLayout()
    /// The kind of the autolink being written (the payload of its node), or nil outside one.
    var autolinkKind: Int?
    /// Footnotes: the labels referenced so far (the first reference of each carries the id its definition links back to), the label of the definition being written, and whether the
    /// section that holds a run of definitions is open.
    var referenced: Set<String> = []
    var currentFootnote = ""
    var inFootnotes = false
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
        closeFootnotes()
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
        if case .leaf(let node) = event, node.kind == .text, headOpen, stack.last?.kind == .codeSpan {
            // A short code span is kept on one line: it would break at a hyphen, in `--flag`.
            if node.range.count <= 40 { out += " data-n" }
        }
        if case .leaf(let node) = event, [.listStart, .linkDestination, .linkTitle].contains(node.kind) {
            attribute(node)
            return
        }
        if case .leaf(let node) = event, node.kind == .footnoteLabel, headOpen {
            currentFootnote = text(node.range)
            out += " id=\"fn-\(Self.anchor(currentFootnote))\""
        }
        closeHead()
        // A run of footnote definitions at the top level sits in one section under a rule; anything else at the top level ends it.
        if stack.isEmpty, inFootnotes {
            switch event {
                case .enter(let node) where node.kind != .footnoteDefinition: closeFootnotes()
                case .leaf: closeFootnotes()
                default: break
            }
        }
        switch event {
            case .enter(let node): enter(node)
            case .exit(let node): exit(node)
            case .leaf(let node): leaf(node)
        }
    }

    /// A definition opens its section if it is the first of a run; its id is written when the label arrives, which is the next event.
    private mutating func enterFootnote() {
        if stack.isEmpty, !inFootnotes {
            out += "<section class=\"footnotes\">\n"
            inFootnotes = true
        }
        currentFootnote = ""
        open(.footnoteDefinition, "div", attributes: " class=\"footnote\"", headOpen: true)
    }

    mutating func closeFootnotes() {
        guard inFootnotes else { return }
        out += "</section>\n"
        inFootnotes = false
    }

    /// An id or fragment for a footnote label: letters and digits as they are, every other byte as `_` and two hex digits, so two labels never share one and nothing needs escaping.
    static func anchor(_ label: String) -> String {
        var result = ""
        for byte in label.utf8 {
            if (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte) {
                result.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                result += "_" + String(byte, radix: 16, uppercase: true)
            }
        }
        return result
    }

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
                open(.paragraph, "p")
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
                rawLanguage = ""
                stack.append(Frame(kind: node.kind, closing: ""))
            case .table:
                tableBody = false
                beforeTable = out
                out = ""
                tableLayout = TableLayout()
                open(.table, "table", closing: "</table>\n")
                out += "\n"
            case .tableRow:
                tableLayout.column = 0
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
                tableLayout.startCell(at: out.utf8.count + 1 + tag.utf8.count)
                open(.tableCell, tag, attributes: alignment)
                tableLayout.cellStart = out.utf8.count
            case .footnoteDefinition: enterFootnote()
            case .emphasis: open(.emphasis, "em")
            case .strong: open(.strong, "strong")
            case .strikethrough: open(.strikethrough, "del")
            case .codeSpan, .math:
                codeDepth += 1
                open(
                    node.kind,
                    "code",
                    attributes: node.kind == .math ? " class=\"math\"" : "",
                    headOpen: node.kind == .codeSpan
                )
            case .link: open(.link, "a", closing: "</a>", headOpen: true)
            case .image: open(.image, "span", attributes: " class=\"image\"", closing: "</span>", headOpen: true)
            case .autolink: autolinkKind = node.payload
            default: break
        }
    }

    mutating func exit(_ node: MarkdownNode) {
        switch node.kind {
            case .footnoteDefinition:
                if referenced.contains(currentFootnote) {
                    out +=
                        "<a class=\"back\" href=\"#fnref-\(Self.anchor(currentFootnote))\" aria-label=\"Back to the text\">\u{21A9}\u{FE0E}</a>"
                }
                closeFrame()
                out += "\n"
            case .codeBlock, .htmlBlock: finishCode(isHTML: node.kind == .htmlBlock)
            case .autolink: autolinkKind = nil
            case .table:
                if tableBody { out += "</tbody>" }
                closeFrame()
                out =
                    beforeTable + "<div class=\"table-wrap\(tableLayout.isWide ? " wide" : "")\">"
                    + tableLayout.apply(to: out) + "</div>\n"
                beforeTable = ""
            case .codeSpan, .math:
                codeDepth -= 1
                closeFrame()
            case .listItem, .list, .blockQuote, .tableRow, .tableCell, .heading, .paragraph:
                if node.kind == .tableCell { tableLayout.endCell(markup: out.utf8, from: tableLayout.cellStart) }
                closeFrame()
                if [.listItem, .blockQuote, .tableRow, .tableCell, .heading].contains(node.kind) { out += "\n" }
            default: closeFrame()
        }
    }

    private mutating func closeFrame() {
        if let frame = stack.popLast() { out += frame.closing }
    }
}
