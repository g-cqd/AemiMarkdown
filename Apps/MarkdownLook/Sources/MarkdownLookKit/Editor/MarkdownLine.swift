/// One line of source as the line commands see it: its indentation, and the marker it starts with, if any.
@available(macOS 26.0, *)
struct MarkdownLine {
    enum List: Equatable { case bullet, task, numbered }

    let text: String
    let indent: String
    /// The line after its indentation.
    private let body: Substring

    init(_ text: String) {
        self.text = text
        let rest = text.drop { $0 == " " || $0 == "\t" }
        indent = String(text[..<rest.startIndex])
        body = rest
    }

    var isBlank: Bool { body.isEmpty }
    var isFence: Bool { body.hasPrefix("```") }
    var isQuoted: Bool { text.hasPrefix(">") }
    var unquoted: String { String(text.hasPrefix("> ") ? text.dropFirst(2) : text.dropFirst(isQuoted ? 1 : 0)) }

    /// The heading's level (1 to 6) when the line is one.
    var heading: Int? {
        let hashes = body.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(hashes) else { return nil }
        let after = body.dropFirst(hashes)
        return after.isEmpty || after.hasPrefix(" ") ? hashes : nil
    }

    var headingBody: String {
        guard let heading else { return String(body) }
        return String(body.dropFirst(heading).drop { $0 == " " })
    }

    /// The kind of list item the line is, and how long its marker is.
    private var marker: (kind: List, length: Int)? {
        for task in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "+ [ ] "] where body.hasPrefix(task) {
            return (.task, task.count)
        }
        if let first = body.first, "-*+".contains(first), body.dropFirst().hasPrefix(" ") { return (.bullet, 2) }
        let digits = body.prefix { $0.isASCII && $0.isNumber }.count
        if (1 ... 9).contains(digits) {
            let after = body.dropFirst(digits)
            if after.hasPrefix(". ") || after.hasPrefix(") ") { return (.numbered, digits + 2) }
        }
        return nil
    }

    var list: List? { marker?.kind }
    var listBody: String { String(body.dropFirst(marker?.length ?? 0)) }
}
