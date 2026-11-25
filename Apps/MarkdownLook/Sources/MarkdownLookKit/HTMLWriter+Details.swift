internal import AemiMarkdown
internal import Foundation

/// `<details>` / `<summary>` emission for ``HTMLWriter``: writes safe `<details class="disclosure">` elements with
/// sanitized `<summary>` inline content and normal Markdown body, always balanced even on malformed input.
@available(macOS 26.0, *)
extension HTMLWriter {
    struct DetailsFrame {
        var stackDepth: Int
        var hasSummary = false
        var awaitingSummaryText = false
        var summaryOpened = false
        var bodyOpened = false
    }

    /// Attempts to handle a completed HTML block as `<details>` / `<summary>` / `</details>` directives.
    /// Returns true if handled, false if the caller should write it as a raw HTML `<pre><code class="source">` block.
    mutating func handleDetailsHTMLBlock(_ raw: String) -> Bool {
        guard let directives = SafeHTML.parseBlock(raw) else { return false }
        let opensAny = directives.contains {
            if case .openDetails = $0 { return true }
            return false
        }
        if detailsFrames.isEmpty, !opensAny { return false }

        for directive in directives {
            applyDetailsDirective(directive, rawBlock: raw)
        }
        return true
    }

    private mutating func applyDetailsDirective(_ directive: SafeHTML.Directive, rawBlock: String) {
        switch directive {
            case .openDetails(let isOpen):
                guard detailsFrames.count < NativeBuilder.maxDetailsDepth else {
                    writeRawHTMLBlock(rawBlock)
                    return
                }
                ensureDetailsBodyOpenIfNested()
                out += isOpen ? "<details class=\"disclosure\" open>" : "<details class=\"disclosure\">"
                detailsFrames.append(DetailsFrame(stackDepth: stack.count))

            case .summary(let label):
                guard !detailsFrames.isEmpty else {
                    writeRawHTMLBlock(rawBlock)
                    return
                }
                let top = detailsFrames.count - 1
                if !detailsFrames[top].hasSummary && !detailsFrames[top].bodyOpened {
                    out += "<summary><span class=\"disclosure-label\">"
                    writeSummaryInline(label)
                    out += "</span></summary>\n"
                    detailsFrames[top].hasSummary = true
                    detailsFrames[top].awaitingSummaryText = false
                } else {
                    ensureDetailsBodyOpen()
                    writeNestedMarkdown(label)
                }

            case .openSummary:
                guard !detailsFrames.isEmpty else {
                    writeRawHTMLBlock(rawBlock)
                    return
                }
                let top = detailsFrames.count - 1
                if !detailsFrames[top].hasSummary && !detailsFrames[top].bodyOpened {
                    out += "<summary><span class=\"disclosure-label\">"
                    detailsFrames[top].summaryOpened = true
                    detailsFrames[top].awaitingSummaryText = true
                }

            case .closeSummary:
                guard !detailsFrames.isEmpty else { return }
                let top = detailsFrames.count - 1
                if detailsFrames[top].summaryOpened {
                    out += "</span></summary>\n"
                    detailsFrames[top].summaryOpened = false
                    detailsFrames[top].awaitingSummaryText = false
                    detailsFrames[top].hasSummary = true
                }

            case .markdown(let body):
                guard !detailsFrames.isEmpty else {
                    writeRawHTMLBlock(rawBlock)
                    return
                }
                let top = detailsFrames.count - 1
                if detailsFrames[top].awaitingSummaryText {
                    writeSummaryInline(body.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    ensureDetailsBodyOpen()
                    writeNestedMarkdown(body)
                }

            case .closeDetails:
                closeOneDetails()
        }
    }

    /// Called before entering a normal block when inside an open `<details>`: ensures `<summary>` is finalized and
    /// `<div class="disclosure-body">` is open. Returns true if the current `<details>` is capturing summary text.
    mutating func prepareDetailsForBlock(kind: NodeKind) -> Bool {
        guard let top = detailsFrames.indices.last else { return false }
        if detailsFrames[top].awaitingSummaryText {
            if kind == .paragraph { return true }
            // Non-paragraph block inside `<summary>` closes the summary and starts the body.
            out += "</span></summary>\n"
            detailsFrames[top].summaryOpened = false
            detailsFrames[top].awaitingSummaryText = false
            detailsFrames[top].hasSummary = true
        }
        ensureDetailsBodyOpen()
        return false
    }

    /// Closes any `<details>` that opened inside a container that is about to close (keeps HTML tags strictly nested).
    mutating func closeDetailsAbove(stackDepth: Int) {
        while let top = detailsFrames.last, top.stackDepth > stackDepth {
            closeOneDetails()
        }
    }

    mutating func closeAllDetails() {
        while !detailsFrames.isEmpty { closeOneDetails() }
    }

    private mutating func closeOneDetails() {
        guard let frame = detailsFrames.popLast() else { return }
        closeFootnotes()
        if frame.summaryOpened {
            out += "</span></summary>\n"
        } else if !frame.hasSummary {
            out += "<summary><span class=\"disclosure-label\">Details</span></summary>\n"
        }
        if frame.bodyOpened { out += "</div>\n" }
        out += "</details>\n"
    }

    private mutating func ensureDetailsBodyOpenIfNested() {
        if !detailsFrames.isEmpty { ensureDetailsBodyOpen() }
    }

    private mutating func ensureDetailsBodyOpen() {
        guard let top = detailsFrames.indices.last else { return }
        if !detailsFrames[top].hasSummary {
            if detailsFrames[top].summaryOpened {
                out += "</span></summary>\n"
                detailsFrames[top].summaryOpened = false
                detailsFrames[top].awaitingSummaryText = false
            } else {
                out += "<summary><span class=\"disclosure-label\">Details</span></summary>\n"
            }
            detailsFrames[top].hasSummary = true
        }
        if !detailsFrames[top].bodyOpened {
            out += "<div class=\"disclosure-body\">\n"
            detailsFrames[top].bodyOpened = true
        }
    }

    private mutating func writeSummaryInline(_ raw: String) {
        let md = SafeHTML.summaryMarkdown(raw)
        guard !md.isEmpty else { return }
        let subdoc = MarkdownParser.parse(Array(md.utf8), extensions: .github)
        let rendered = options.body(subdoc, embedsDiagramStyle: embedsDiagramStyle)
        // Strip a single outer `<p>…</p>` wrapper when the summary is one paragraph so `<summary>` holds inline markup.
        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<p>"), trimmed.hasSuffix("</p>") {
            let inner = String(trimmed.dropFirst(3).dropLast(4))
            if !inner.contains("</p>") {
                out += inner
                return
            }
        }
        out += trimmed
    }

    private mutating func writeNestedMarkdown(_ body: String) {
        let subdoc = MarkdownParser.parse(Array(body.utf8), extensions: .github)
        out += options.body(subdoc, embedsDiagramStyle: embedsDiagramStyle)
    }

    private mutating func writeRawHTMLBlock(_ raw: String) {
        out += "<pre><code class=\"source\">"
        HTMLEscaper.escape(Array(raw.utf8), into: &out)
        if !raw.isEmpty { out.append(0x0A) }
        out += "</code></pre>\n"
    }
}
