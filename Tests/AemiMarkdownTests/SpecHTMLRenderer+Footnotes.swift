@testable import AemiMarkdown

extension SpecHTMLRenderer {
    /// GitHub's output of a reference: a superscript link to the definition, numbered by first reference.
    mutating func writeFootnoteReference(_ node: MarkdownNode) {
        let label = Array(document.source[node.range])
        let key = Self.key(label)
        let (number, occurrence) = footnotes.reference(key)
        var escaped: [UInt8] = []
        HTMLEscaping.href(label, into: &escaped)
        let suffix = occurrence > 1 ? "-\(occurrence)" : ""
        write("<sup class=\"footnote-ref\"><a href=\"#fn-")
        out.append(contentsOf: escaped)
        write("\" id=\"fnref-")
        out.append(contentsOf: escaped)
        write("\(suffix)\" data-footnote-ref>\(number)</a></sup>")
    }

    static func key(_ label: [UInt8]) -> [UInt8] {
        var key: [UInt8] = []
        ReferenceTable.normalize(label, into: &key)
        return key
    }

    /// The section of definitions, in the order of first reference, each with a link back to every reference. Definitions nobody referenced are left out.
    mutating func writeFootnotes() {
        let referenced = footnotes.order.filter { footnotes.definitions[$0] != nil }
        guard !referenced.isEmpty else { return }
        carriageReturn()
        write("<section class=\"footnotes\" data-footnotes>\n<ol>\n")
        for key in referenced {
            guard var events = footnotes.definitions[key] else { continue }
            var labelBytes: [UInt8] = []
            if case .leaf(let first)? = events.first, first.kind == .footnoteLabel {
                labelBytes = Array(document.source[first.range])
                events.removeFirst()
            }
            var content = SpecHTMLRenderer(document, tagFilter: tagFilter)
            for event in events { content.handle(event) }
            var escaped: [UInt8] = []
            HTMLEscaping.href(labelBytes, into: &escaped)
            let count = footnotes.references[key] ?? 1
            let number = (footnotes.order.firstIndex(of: key) ?? 0) + 1
            var backrefs = ""
            for occurrence in 1 ... count {
                let suffix = occurrence > 1 ? "-\(occurrence)" : ""
                let index = occurrence > 1 ? "\(number)-\(occurrence)" : "\(number)"
                let marker = occurrence > 1 ? "<sup class=\"footnote-ref\">\(occurrence)</sup>" : ""
                if occurrence > 1 { backrefs += " " }
                backrefs +=
                    "<a href=\"#fnref-\(String(decoding: escaped, as: UTF8.self))\(suffix)\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"\(index)\" aria-label=\"Back to reference \(index)\">↩\(marker)</a>"
            }
            write("<li id=\"fn-\(String(decoding: escaped, as: UTF8.self))\">\n")
            var body = String(decoding: content.out, as: UTF8.self)
            if body.hasSuffix("</p>\n") {
                body.removeLast(5)
                body += " " + backrefs + "</p>\n"
            } else {
                body += backrefs + "\n"
            }
            write(body)
            write("</li>\n")
        }
        write("</ol>\n</section>\n")
    }
}
