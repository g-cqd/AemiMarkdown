internal import AemiMarkdown
internal import Foundation
internal import SwiftUI

/// `<details>` / `<summary>` assembly for ``NativeBuilder``: collects rows emitted between `<details>` and `</details>`
/// into nested ``NativeDetails`` blocks (bounded to ``maxDetailsDepth`` to prevent pathological nesting).
@available(macOS 26.0, *)
extension NativeBuilder {
    /// Maximum nesting depth of `<details>` blocks. Past this depth, nested directives are shown as literal HTML blocks.
    static let maxDetailsDepth = 16

    struct DetailsState {
        var isOpen: Bool
        var summary: AttributedString = AttributedString()
        var awaitingSummaryText = false
        var hasSummary = false
        var rows: [NativeRow] = []
        var sources: [String] = []
        /// Saved outer `rootLast` so rows inside `<details>` get fresh top-level spacing starting at gap 0.
        var savedRootLast: Sibling?
        /// Depth of `frames` when this `<details>` opened (so nested quotes/lists inside stay scoped to it).
        var frameDepth: Int
    }

    /// Handles a completed HTML block that may contain `<details>`, `<summary>`, or `</details>`.
    /// Returns true if the block was consumed as disclosure markup, false if it should be emitted as raw HTML code.
    mutating func handleDetailsHTMLBlock(_ raw: String) -> Bool {
        guard let directives = SafeHTML.parseBlock(raw) else { return false }
        // If there are only closing tags (`</details>` or `</summary>`) with no open details frame, keep them as raw HTML.
        let opensAny = directives.contains {
            if case .openDetails = $0 { return true }
            return false
        }
        if detailsStack.isEmpty, !opensAny { return false }

        for directive in directives {
            applyDirective(directive, rawBlock: raw)
        }
        return true
    }

    private mutating func applyDirective(_ directive: SafeHTML.Directive, rawBlock: String) {
        switch directive {
            case .openDetails(let isOpen):
                guard detailsStack.count < Self.maxDetailsDepth else {
                    emitRawHTMLBlock(rawBlock)
                    return
                }
                let state = DetailsState(
                    isOpen: isOpen,
                    sources: [isOpen ? "<details open>" : "<details>"],
                    savedRootLast: rootLast,
                    frameDepth: frames.count
                )
                rootLast = nil
                detailsStack.append(state)
                span = nil
                pendingSource = nil

            case .summary(let label):
                guard !detailsStack.isEmpty else {
                    emitRawHTMLBlock(rawBlock)
                    return
                }
                let top = detailsStack.count - 1
                if !detailsStack[top].hasSummary {
                    detailsStack[top].summary = parseSummaryInline(label)
                    detailsStack[top].hasSummary = true
                    detailsStack[top].awaitingSummaryText = false
                    detailsStack[top].sources.append("<summary>\(label)</summary>")
                } else {
                    parseAndEmitInlineMarkdown(label)
                }

            case .openSummary:
                guard !detailsStack.isEmpty else {
                    emitRawHTMLBlock(rawBlock)
                    return
                }
                let top = detailsStack.count - 1
                if !detailsStack[top].hasSummary { detailsStack[top].awaitingSummaryText = true }

            case .closeSummary:
                guard !detailsStack.isEmpty else { return }
                let top = detailsStack.count - 1
                if detailsStack[top].awaitingSummaryText {
                    detailsStack[top].awaitingSummaryText = false
                    detailsStack[top].hasSummary = true
                }

            case .markdown(let body):
                guard !detailsStack.isEmpty else {
                    emitRawHTMLBlock(rawBlock)
                    return
                }
                let top = detailsStack.count - 1
                if detailsStack[top].awaitingSummaryText {
                    let parsed = parseSummaryInline(body.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !detailsStack[top].summary.characters.isEmpty {
                        detailsStack[top].summary += AttributedString(" ")
                    }
                    detailsStack[top].summary += parsed
                } else {
                    parseAndEmitInlineMarkdown(body)
                }

            case .closeDetails:
                closeOneDetails()
        }
    }

    /// Closes the innermost open `<details>` block and emits its `.details` row into its parent (either an outer
    /// `<details>` or the document).
    mutating func closeOneDetails() {
        guard var closed = detailsStack.popLast() else { return }
        rootLast = closed.savedRootLast
        closed.sources.append("</details>")
        let fullSource = closed.sources.joined(separator: "\n\n")
        // Re-index child rows sequentially from 0 so SwiftUI `ForEach` ids are clean inside the disclosure.
        let childRows = closed.rows.enumerated()
            .map { index, row in
                NativeRow(
                    id: index,
                    guides: row.guides,
                    gap: index == 0 ? 0 : row.gap,
                    content: row.content,
                    source: row.source
                )
            }
        pendingSource = fullSource
        emit(.details(NativeDetails(summary: closed.summary, isOpen: closed.isOpen, rows: childRows)), kind: .box)
    }

    /// Closes any unclosed `<details>` blocks at end-of-document so no content is silently dropped.
    mutating func flushOpenDetails() {
        while !detailsStack.isEmpty { closeOneDetails() }
    }

    /// Parses summary inline Markdown/HTML (`SafeHTML.summaryMarkdown`) into a styled `AttributedString`.
    private func parseSummaryInline(_ raw: String) -> AttributedString {
        let md = SafeHTML.summaryMarkdown(raw)
        let subdoc = MarkdownParser.parse(Array(md.utf8), extensions: .github)
        let built = NativeDocument(subdoc, settings: settings)
        var combined = AttributedString()
        for (index, row) in built.rows.enumerated() {
            if index > 0 { combined += AttributedString(" ") }
            if case .text(let t) = row.content { combined += t.string }
        }
        return combined
    }

    /// Parses Markdown lines that appeared inside a `<details>` HTML block (without a blank line separating them from
    /// `<details>` or `</summary>`) and appends the resulting rows into the current `<details>`.
    private mutating func parseAndEmitInlineMarkdown(_ markdown: String) {
        let subdoc = MarkdownParser.parse(Array(markdown.utf8), extensions: .github)
        let built = NativeDocument(subdoc, settings: settings)
        for row in built.rows {
            pendingSource = row.source
            let sibling: Sibling =
                switch row.content {
                    case .text(let t):
                        switch t.style {
                            case .heading(let level): .heading(level)
                            case .alertTitle: .title
                            default: .prose
                        }
                    case .rule: .rule
                    case .footnoteRule: .notes
                    default: .box
                }
            emit(row.content, kind: sibling)
        }
    }

    /// Emits a raw HTML block verbatim as a `.code(..., isHTML: true)` row.
    mutating func emitRawHTMLBlock(_ raw: String) {
        pendingSource = raw
        emit(
            .code(NativeCode(language: "", raw: raw, shown: shown(raw, language: "", isHTML: true), isHTML: true)),
            kind: .box
        )
    }
}
