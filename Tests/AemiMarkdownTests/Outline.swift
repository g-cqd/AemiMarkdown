@testable import AemiMarkdown

/// A document as an indented outline of its nodes, so a test can say what the parser made without a renderer.
enum Outline {
    static func of(_ document: MarkdownDocument) -> String {
        var lines: [String] = []
        var depth = 0
        for event in document.events {
            switch event {
                case .enter(let node):
                    lines.append(String(repeating: "  ", count: depth) + describe(node, document))
                    depth += 1
                case .exit: depth -= 1
                case .leaf(let node): lines.append(String(repeating: "  ", count: depth) + describe(node, document))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ node: MarkdownNode, _ document: MarkdownDocument) -> String {
        var text = "\(node.kind)"
        if node.payload != 0 { text += "[\(node.payload)]" }
        if !node.range.isEmpty {
            text += " " + String(decoding: document.source[node.range], as: UTF8.self).debugDescription
        }
        if node.kind == .listStart || node.kind == .virtualSpaces { text += " \(node.value)" }
        return text
    }
}
