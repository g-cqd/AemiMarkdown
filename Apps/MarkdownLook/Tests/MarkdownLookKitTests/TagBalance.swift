/// Checks that HTML the viewer wrote is balanced: every start tag closed in order, void elements aside, and no tag, attribute or text left open. It reads the writer's own dialect (lower-case
/// names, quoted attributes), which is what makes it a check on the writer and not a parser of the web.
enum TagBalance {
    static let void: Set<String> = ["br", "hr", "input", "meta", "img", "path", "rect", "polygon", "polyline", "circle"]

    /// Nil when balanced, otherwise what is wrong.
    static func problem(in html: String) -> String? {
        var stack: [String] = []
        var iterator = html.unicodeScalars.makeIterator()
        var inStyle = false
        while let scalar = iterator.next() {
            guard scalar == "<" else {
                if scalar == ">" && !inStyle { return "a bare > in text" }
                continue
            }
            var tag = ""
            var closing = false
            var selfClosed = false
            var quote: Unicode.Scalar?
            var inName = true
            var terminated = false
            var previous: Unicode.Scalar = "<"
            while let next = iterator.next() {
                if let open = quote {
                    if next == open { quote = nil }
                    if next == "<" { return "a < inside an attribute of <\(tag)>" }
                    previous = next
                    continue
                }
                if next == "\"" { quote = next }
                if next == ">" {
                    terminated = true
                    selfClosed = previous == "/"
                    break
                }
                if next == "<" { return "a < inside <\(tag)" }
                if tag.isEmpty && next == "/" {
                    closing = true
                } else if inName && (next == " " || next == "\n") {
                    inName = false
                } else if inName && next != "/" {
                    tag.unicodeScalars.append(next)
                }
                previous = next
            }
            if !terminated { return "<\(tag) never ends" }
            if tag == "style" && !closing { inStyle = true }
            if tag == "style" && closing { inStyle = false }
            if tag.hasPrefix("!") || tag.isEmpty { continue }
            if closing {
                guard stack.popLast() == tag else { return "unbalanced </\(tag)>" }
            } else if !void.contains(tag) && !selfClosed {
                stack.append(tag)
            }
            if tag == "style" && !closing {
                // The style's text runs to its end tag; skip it.
                var tail = ""
                while let next = iterator.next() {
                    tail.unicodeScalars.append(next)
                    if tail.hasSuffix("</style>") { break }
                }
                stack.removeLast()
            }
        }
        return stack.isEmpty ? nil : "unclosed \(stack)"
    }
}
