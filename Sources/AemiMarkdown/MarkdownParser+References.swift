extension MarkdownParser {
    /// Removes the link reference definitions at the start of the open paragraph at `index`, and records them. Not built yet: a paragraph keeps all its lines.
    mutating func resolveReferenceDefinitions(in index: Int) {}

    /// The same for a paragraph that is closing. When definitions use every line, the paragraph disappears.
    mutating func resolveReferenceDefinitionsAtClose(_ block: BlockState.Open) {
        state.pending.append(.init(slot: block.slot, firstLine: block.firstLine, lineCount: block.lineCount))
    }
}
