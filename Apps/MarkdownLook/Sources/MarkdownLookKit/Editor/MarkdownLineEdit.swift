/// The commands that mark whole lines (a heading, the lists, a quote, a code block): they act on every line the selection touches
/// and leave those lines selected.
@available(macOS 26.0, *)
enum MarkdownLineEdit {
    static func apply(_ command: MarkdownCommand, in units: [UInt16], _ range: Range<Int>) -> MarkdownEdit {
        let newline = UInt16(UInt8(ascii: "\n"))
        // A selection that ends at the start of a line does not touch that line.
        var high = range.upperBound
        if high > range.lowerBound, units[high - 1] == newline { high -= 1 }
        let start = (units[..<range.lowerBound].lastIndex(of: newline)).map { $0 + 1 } ?? 0
        let end = units[high...].firstIndex(of: newline) ?? units.count
        let lines = units[start ..< end].split(separator: newline, omittingEmptySubsequences: false)
            .map {
                MarkdownLine(String(decoding: $0, as: UTF16.self))
            }
        let replacement = changed(lines, by: command).joined(separator: "\n")
        return MarkdownEdit(
            range: start ..< end,
            replacement: replacement,
            selection: start ..< (start + replacement.utf16.count)
        )
    }

    private static func changed(_ lines: [MarkdownLine], by command: MarkdownCommand) -> [String] {
        // The lines a mark goes on: those with text, or all of them when none has any (a mark typed on an empty line).
        let hasText = lines.contains { !$0.isBlank }
        let marked = lines.map { !hasText || !$0.isBlank }
        func all(_ holds: (MarkdownLine) -> Bool) -> Bool { zip(lines, marked).allSatisfy { !$1 || holds($0) } }
        switch command {
            case .heading(let asked):
                let level = min(max(asked, 1), 6)
                let remove = all { $0.heading == level }
                return zip(lines, marked)
                    .map { line, mark in
                        guard mark else { return line.text }
                        return line.indent + (remove ? "" : String(repeating: "#", count: level) + " ")
                            + line.headingBody
                    }
            case .bulletList: return list(lines, marked, remove: all { $0.list == .bullet }) { _ in "- " }
            case .taskList: return list(lines, marked, remove: all { $0.list == .task }) { _ in "- [ ] " }
            case .numberedList: return list(lines, marked, remove: all { $0.list == .numbered }) { "\($0). " }
            case .quote:
                let remove = lines.allSatisfy(\.isQuoted)
                return lines.map { remove ? $0.unquoted : ($0.text.isEmpty ? ">" : "> " + $0.text) }
            case .codeBlock:
                if lines.count >= 2, lines[0].isFence, lines[lines.count - 1].isFence {
                    return lines.dropFirst().dropLast().map(\.text)
                }
                return ["```"] + lines.map(\.text) + ["```"]
            case .bold, .italic, .strikethrough, .code, .link: return lines.map(\.text)
        }
    }

    /// Sets (or takes away) the list marker of each marked line; `marker` is given the line's number among the marked ones.
    private static func list(
        _ lines: [MarkdownLine],
        _ marked: [Bool],
        remove: Bool,
        marker: (Int) -> String
    ) -> [String] {
        var number = 0
        return zip(lines, marked)
            .map { line, mark in
                guard mark else { return line.text }
                number += 1
                return line.indent + (remove ? "" : marker(number)) + line.listBody
            }
    }
}
