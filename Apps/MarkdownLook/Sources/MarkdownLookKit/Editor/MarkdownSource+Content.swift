@available(macOS 26.0, *)
extension MarkdownSource {
    /// What a source's text is read as.
    public enum Content: Sendable, Hashable {
        /// Markdown: parsed, kept in step with each edit, drawn as a page.
        case markdown
        /// One Mermaid diagram.
        case diagram
        /// Text that is only shown as source: never parsed, no page. A long log is one paragraph to a Markdown parser, read
        /// again whole at each key.
        case plain
    }
}
