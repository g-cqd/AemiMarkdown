import Testing

@testable import AemiMarkdown

/// What an edit test compares: each top-level block as the text it holds and the events it makes, without where its bytes are.
enum EditOracle {
    /// The block's events with every source range replaced by the bytes it names, so a block that moved is the same signature.
    static func signature(_ document: MarkdownDocument, _ block: MarkdownBlock) -> [String] {
        var result: [String] = []
        for event in document.events(of: block) {
            switch event {
                case .enter(let node): result.append("enter \(node.kind) \(node.payload)")
                case .exit(let node): result.append("exit \(node.kind)")
                case .leaf(let node):
                    result.append(
                        "leaf \(node.kind) \(node.payload) \(node.value) \(String(decoding: document.source[node.range], as: UTF8.self))"
                    )
            }
        }
        return result
    }

    static func signatures(_ document: MarkdownDocument) -> [[String]] {
        document.topLevelBlocks.map { signature(document, $0) }
    }

    /// Whether the editor's document is what a fresh parse of its source gives, and the change tells the truth about the old and the new blocks:
    /// the ones it leaves out are the same blocks, and the counts add up. Returns what is wrong, empty when nothing is.
    static func problems(
        old: MarkdownDocument,
        editor: MarkdownEditor,
        change: MarkdownChange,
        extensions: MarkdownExtensions
    ) -> [String] {
        var problems: [String] = []
        let new = editor.document
        let fresh = MarkdownParser.parse(Array(new.source), extensions: extensions)
        let freshSignatures = signatures(fresh)
        let newSignatures = signatures(new)
        if newSignatures != freshSignatures { problems.append("the edited document is not the fresh parse") }
        if fresh.topLevelBlocks.map(\.contentHash) != new.topLevelBlocks.map(\.contentHash) {
            problems.append("hashes differ from the fresh parse")
        }
        if fresh.topLevelBlocks.map(\.sourceRange) != new.topLevelBlocks.map(\.sourceRange) {
            problems.append("ranges differ from the fresh parse")
        }
        // Tape for tape: what the editor holds is what a fresh parse of the same bytes writes.
        var reference = MarkdownParser(extensions: extensions)
        reference.append(Array(new.source))
        reference.finish()
        let held = editor.parser
        if held.blocks.committedSlots != reference.blocks.committedSlots {
            problems.append("block tape differs from the fresh parse")
        }
        if held.inlines.committedSlots != reference.inlines.committedSlots {
            problems.append("inline tape differs from the fresh parse")
        }
        if held.topIndex.committedSlots != reference.topIndex.committedSlots {
            problems.append("block index differs from the fresh parse")
        }
        if held.stamps.committedSlots != reference.stamps.committedSlots {
            problems.append("stamps differ from the fresh parse")
        }
        if held.diagnostics != reference.diagnostics { problems.append("diagnostics differ from the fresh parse") }
        let oldSignatures = signatures(old)
        guard change.firstBlock + change.removedBlocks <= oldSignatures.count,
            change.firstBlock + change.insertedBlocks <= newSignatures.count
        else {
            return problems + ["the change names blocks that do not exist: \(change)"]
        }
        if oldSignatures.count - change.removedBlocks != newSignatures.count - change.insertedBlocks {
            problems.append("the counts do not add up")
        }
        for ordinal in 0 ..< change.firstBlock where oldSignatures[ordinal] != newSignatures[ordinal] {
            problems.append("block \(ordinal) before the change differs")
        }
        let oldTail = change.firstBlock + change.removedBlocks
        let newTail = change.firstBlock + change.insertedBlocks
        if oldSignatures[oldTail...] != newSignatures[newTail...] {
            problems.append("a block after the change differs")
        }
        return problems
    }
}
