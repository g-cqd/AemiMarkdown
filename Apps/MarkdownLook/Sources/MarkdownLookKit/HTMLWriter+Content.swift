internal import AemiMarkdown

extension HTMLWriter {
    /// The attribute-giving leaves: a list's start number, a link's destination and title.
    mutating func attribute(_ node: MarkdownNode) {
        guard headOpen else { return }
        switch node.kind {
            case .listStart: if node.value != 1 { out += " start=\"\(node.value)\"" }
            case .linkDestination:
                let destination = String(decoding: document.decode(node.range), as: UTF8.self)
                if stack.last?.kind == .link, HTMLText.isSafeDestination(destination) {
                    out += " href=\"\(HTMLText.escaped(destination))\""
                }
            default:
                if node.kind == .linkTitle {
                    out +=
                        " title=\"\(HTMLText.escaped(String(decoding: document.decode(node.range), as: UTF8.self)))\""
                }
        }
    }

    mutating func leaf(_ node: MarkdownNode) {
        switch node.kind {
            case .text:
                if let kind = autolinkKind { return writeAutolink(node, kind: kind) }
                write(text(node.range))
            case .entity: write(String(decoding: document.decode(node.range), as: UTF8.self))
            case .htmlInline: out += HTMLText.escaped(text(node.range))
            case .softBreak: out += codeDepth > 0 ? " " : "\n"
            case .hardBreak: out += "<br>\n"
            case .thematicBreak: out += "<hr>\n"
            case .taskMarker: out += "<input type=\"checkbox\" disabled\(node.payload == 1 ? " checked" : "")> "
            case .footnoteReference: out += "<sup class=\"fn\">\(HTMLText.escaped(text(node.range)))</sup>"
            case .footnoteLabel: out += "<span class=\"label\">[^\(HTMLText.escaped(text(node.range)))]</span> "
            case .infoString:
                let word = document.source[node.range].prefix { $0 != 0x20 && $0 != 0x09 }
                language = HTMLText.escaped(
                    String(decoding: document.decode(word.startIndex ..< word.endIndex), as: UTF8.self)
                )
            case .virtualSpaces: pendingSpaces = node.value
            case .codeLine:
                codeLines.append(String(repeating: " ", count: pendingSpaces) + text(node.range))
                pendingSpaces = 0
            default: break
        }
    }

    /// Prose goes through smart punctuation; code does not.
    mutating func write(_ string: String) {
        out += HTMLText.escaped(options.smartPunctuation && codeDepth == 0 ? smart.apply(string) : string)
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
        let code = codeLines.joined(separator: "\n")
        if !isHTML, options.drawsDiagrams, language.lowercased() == "mermaid",
            let svg = MermaidFence.svg(Array(code.utf8), embedsStyle: embedsDiagramStyle)
        {
            out += "<figure>" + svg + "</figure>\n"
            return
        }
        let classes = isHTML ? " class=\"source\"" : (language.isEmpty ? "" : " class=\"language-\(language)\"")
        out += "<pre><code\(classes)>" + HTMLText.escaped(code) + (code.isEmpty ? "" : "\n") + "</code></pre>\n"
    }
}
