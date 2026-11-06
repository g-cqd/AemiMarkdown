internal import AemiMarkdown

extension HTMLWriter {
    /// The attribute-giving leaves: a list's start number, a link's destination and title.
    mutating func attribute(_ node: MarkdownNode) {
        guard headOpen else { return }
        switch node.kind {
            case .listStart: if node.value != 1 { out += " start=\"\(node.value)\"" }
            case .linkDestination:
                let destination = document.decode(node.range)
                if stack.last?.kind == .link, HTMLText.isSafeDestination(bytes: destination) {
                    out += " href=\""
                    HTMLEscaper.escape(destination, into: &out)
                    out.append(0x22)
                }
            default:
                if node.kind == .linkTitle {
                    out += " title=\""
                    HTMLEscaper.escape(document.decode(node.range), into: &out)
                    out.append(0x22)
                }
        }
    }

    mutating func leaf(_ node: MarkdownNode) {
        switch node.kind {
            case .text:
                if let kind = autolinkKind { return writeAutolink(node, kind: kind) }
                writeSource(node.range)
            case .entity: write(document.decode(node.range))
            case .htmlInline: writeSource(node.range, smart: false)
            case .softBreak: out += codeDepth > 0 ? " " : "\n"
            case .hardBreak: out += "<br>\n"
            case .thematicBreak: out += "<hr>\n"
            case .taskMarker: out += "<input type=\"checkbox\" disabled\(node.payload == 1 ? " checked" : "")> "
            case .footnoteReference:
                let label = text(node.range)
                let anchor = Self.anchor(label)
                // The first reference to a footnote is where its definition links back to.
                let id = referenced.insert(label).inserted ? " id=\"fnref-\(anchor)\"" : ""
                out += "<sup class=\"fn\"><a href=\"#fn-\(anchor)\"\(id)>\(HTMLText.escaped(label))</a></sup>"
            case .footnoteLabel: out += "<span class=\"label\">\(HTMLText.escaped(text(node.range)))</span>"
            case .infoString:
                let word = document.source[node.range].prefix { $0 != 0x20 && $0 != 0x09 }
                rawLanguage = String(decoding: document.decode(word.startIndex ..< word.endIndex), as: UTF8.self)
                language = HTMLText.escaped(rawLanguage)
            case .virtualSpaces: pendingSpaces = node.value
            case .codeLine:
                if codeLineCount > 0 { codeBytes.append(0x0A) }
                codeLineCount += 1
                if pendingSpaces > 0 { codeBytes.append(contentsOf: repeatElement(0x20, count: pendingSpaces)) }
                codeBytes.append(contentsOf: document.source[node.range])
                pendingSpaces = 0
            default: break
        }
    }

    /// Prose goes through smart punctuation; code does not. Straight from the source: no `String` in between.
    mutating func writeSource(_ range: Range<Int>, smart useSmart: Bool = true) {
        let smartOn = useSmart && options.smartPunctuation && codeDepth == 0
        document.source.withUnsafeBufferPointer { source in
            let slice = unsafe UnsafeBufferPointer(rebasing: source[range])
            unsafe HTMLEscaper.escape(slice, into: &out, smart: &smart, smartOn: smartOn)
        }
    }

    mutating func write(_ bytes: [UInt8]) {
        let smartOn = options.smartPunctuation && codeDepth == 0
        bytes.withUnsafeBufferPointer { unsafe HTMLEscaper.escape($0, into: &out, smart: &smart, smartOn: smartOn) }
    }

    /// An autolink's text is its target: `<https://a.b>`, `<a@b.c>`, a bare `www.a.b`.
    mutating func writeAutolink(_ node: MarkdownNode, kind: Int) {
        let shown = text(node.range)
        var target = shown
        if kind == 1, !shown.hasPrefix("mailto:") { target = "mailto:" + shown }
        if kind == 2, !shown.contains(":") { target = "http://" + shown }
        if HTMLText.isSafeDestination(target) {
            out += "<a href=\"\(HTMLText.escaped(target))\">\(HTMLText.escaped(shown))</a>"
        } else {
            out += HTMLText.escaped(shown)
        }
    }

    /// The end of a code block: a mermaid fence as a figure with its diagram, any other fence or an HTML block as preformatted text.
    mutating func finishCode(isHTML: Bool) {
        inCode = false
        stack.removeLast()
        let code = codeBytes
        codeBytes = []
        codeLineCount = 0
        if !isHTML, options.drawsDiagrams, language.lowercased() == "mermaid",
            let svg = MermaidFence.svg(Self.wellFormed(code), embedsStyle: embedsDiagramStyle)
        {
            out += "<figure>" + svg + "</figure>\n"
            return
        }
        let classes = isHTML ? " class=\"source\"" : (language.isEmpty ? "" : " class=\"language-\(language)\"")
        // The language the fence names, shown in the corner: a label for the eye that a selection does not take.
        let labelled = !(isHTML || language.isEmpty || !options.settings.showsLanguage)
        if labelled { out += "<div class=\"code\"><span class=\"lang\">\(language)</span>" }
        out += "<pre><code\(classes)>"
        if !isHTML, options.settings.highlightsCode, code.count <= CodeHighlighter.byteLimit,
            let known = CodeHighlighter.language(for: rawLanguage)
        {
            CodeHighlighter.html(Self.wellFormed(code), language: known, into: &out)
        } else {
            HTMLEscaper.escape(code, into: &out)
        }
        if !code.isEmpty { out.append(0x0A) }
        out += "</code></pre>\n"
        if labelled { out += "</div>\n" }
    }

    /// The end of the document's head: a table, as GitHub draws one, or its lines as code when it is not a mapping or does not read.
    mutating func finishFrontMatter() {
        guard let table = FrontMatterTable(document) else { return finishCode(isHTML: false) }
        inCode = false
        stack.removeLast()
        codeBytes = []
        codeLineCount = 0
        out += "<div class=\"table-wrap front-matter\"><table>\n<thead><tr>"
        for key in table.keys { out += "<th>\(HTMLText.escaped(key))</th>" }
        out += "</tr></thead><tbody><tr>"
        for value in table.values { out += "<td>\(HTMLText.escaped(value))</td>" }
        out += "</tr></tbody></table></div>\n"
    }

    /// `code` as the scanners and the diagram engine read it: UTF-8 with any ill-formed sequence replaced, as a `String` would hold it.
    static func wellFormed(_ code: [UInt8]) -> [UInt8] {
        code.contains { $0 >= 0x80 } ? Array(String(decoding: code, as: UTF8.self).utf8) : code
    }
}
