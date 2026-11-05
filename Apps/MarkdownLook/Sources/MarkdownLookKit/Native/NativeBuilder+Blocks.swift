internal import AemiLexers
internal import AemiMarkdown
internal import AemiMermaidLayout
internal import AemiMermaidScene
internal import AemiMermaidSyntax
internal import Foundation
internal import SwiftUI

extension NativeBuilder {
    mutating func exitCode() {
        guard let state = code else { return }
        code = nil
        let raw = state.lines.joined(separator: "\n")
        pendingSource = state.isHTML ? raw : "```\(state.language)\n\(raw)\n```"
        if !state.isHTML, settings.drawsDiagrams, state.language.lowercased() == "mermaid",
            let diagram = Self.diagram(raw)
        {
            emit(.diagram(diagram), kind: .box)
            return
        }
        emit(
            .code(
                NativeCode(
                    language: state.isHTML ? "" : state.language,
                    raw: raw,
                    shown: shown(raw, language: state.language, isHTML: state.isHTML),
                    isHTML: state.isHTML
                )
            ),
            kind: .box
        )
    }

    func shown(_ raw: String, language: String, isHTML: Bool) -> AttributedString {
        let expanded = Self.expandTabs(raw, size: settings.tabSize)
        var text = AttributedString(expanded)
        guard !isHTML, settings.highlightsCode, expanded.utf8.count <= CodeHighlighter.byteLimit,
            let known = CodeHighlighter.language(for: language)
        else { return text }
        let bytes = Array(expanded.utf8)
        for (range, kind) in CodeHighlighter.spans(bytes, language: known) {
            let start = text.utf8.index(text.startIndex, offsetBy: range.lowerBound)
            let end = text.utf8.index(text.startIndex, offsetBy: range.upperBound)
            text[start ..< end].foregroundColor = NativeTheme.token(kind)
            if kind == "c" { text[start ..< end].inlinePresentationIntent = .emphasized }
        }
        return text
    }

    /// Tabs to the next multiple of `size` columns, line by line.
    static func expandTabs(_ text: String, size: Int) -> String {
        guard text.contains("\t") else { return text }
        var out = ""
        var column = 0
        for character in text {
            if character == "\t" {
                let width = size - column % size
                out += String(repeating: " ", count: width)
                column += width
            } else {
                out.append(character)
                column = character.isNewline ? 0 : column + 1
            }
        }
        return out
    }

    static func diagram(_ source: String) -> NativeDiagram? {
        let parse = MermaidParse.parse(Array(source.utf8), limits: .default)
        if case .refused = parse.result { return nil }
        if case .pie(let pie) = parse.result { return pie.slices.isEmpty ? nil : .pie(pie) }
        var scene = DiagramScene()
        guard case .drawn = MermaidLayout.lay(parse.result, limits: .default, into: &scene) else { return nil }
        return .scene(scene)
    }

    mutating func exitTable() {
        guard let state = table else { return }
        table = nil
        emit(.table(NativeTable(alignments: state.alignments, header: state.header, rows: state.rows)), kind: .box)
    }
}

extension NativeBuilder {
    /// Takes in the bytes a leaf of the block names.
    mutating func widen(_ range: Range<Int>) {
        span =
            span.map { Swift.min($0.lowerBound, range.lowerBound) ..< Swift.max($0.upperBound, range.upperBound) }
            ?? range
    }

    /// The Markdown a row is made from, for copying: the lines its leaves are on (whole lines, so a heading keeps its `#` and an item its marker), a code block as its fence, a rule as a rule.
    mutating func takeSource(for content: NativeContent) -> String {
        defer {
            span = nil
            pendingSource = nil
        }
        if let pendingSource { return pendingSource }
        if case .rule = content { return "---" }
        guard let span, span.upperBound <= document.source.count else { return "" }
        var start = span.lowerBound
        while start > 0, document.source[start - 1] != 0x0A { start -= 1 }
        var end = span.upperBound
        while end < document.source.count, document.source[end] != 0x0A { end += 1 }
        return String(decoding: document.source[start ..< end], as: UTF8.self)
    }
}
