@testable import AemiMarkdown

/// Checks that a document's tapes are well formed, whatever the input was: what a reader relies on when it walks them without bounds checks of its own.
enum TapeValidator {
    /// The first problem found, or nil.
    static func problem(in document: MarkdownDocument) -> String? {
        if let problem = check(document.blocks, inlines: document.inlines, source: document.source) { return problem }
        var depth = 0
        var maxDepth = 0
        for event in document.events {
            switch event {
                case .enter:
                    depth += 1
                    maxDepth = Swift.max(maxDepth, depth)
                case .exit: depth -= 1
                case .leaf: break
            }
            if depth < 0 { return "an exit with no enter" }
        }
        return depth == 0 ? nil : "\(depth) containers never exit"
    }

    private static func check(_ blocks: SlotTape, inlines: SlotTape, source: ContiguousArray<UInt8>) -> String? {
        for index in 0 ..< blocks.count {
            let slot = blocks[index]
            switch Slot.shape(slot) {
                case .container:
                    let end = Slot.low(slot)
                    if end <= index || end > blocks.count {
                        return "block \(index): end \(end) outside \(index + 1)...\(blocks.count)"
                    }
                case .leafBlock:
                    let run = Slot.low(slot)
                    guard run < inlines.count else { return "block \(index): inline run \(run) past the tape" }
                    var cursor = run
                    while cursor < inlines.count, Slot.kind(inlines[cursor]) != .runEnd { cursor += 1 }
                    if cursor == inlines.count { return "block \(index): inline run never ends" }
                case .range:
                    if let bad = rangeProblem(slot, source.count) { return "block \(index): \(bad)" }
                case .marker: break
            }
        }
        for index in 0 ..< inlines.count {
            let slot = inlines[index]
            switch Slot.shape(slot) {
                case .container:
                    let end = Slot.low(slot)
                    if end <= index || end > inlines.count {
                        return "inline \(index): end \(end) outside \(index + 1)...\(inlines.count)"
                    }
                case .range:
                    if let bad = rangeProblem(slot, source.count) { return "inline \(index): \(bad)" }
                default: break
            }
        }
        return nil
    }

    private static func rangeProblem(_ slot: UInt64, _ sourceCount: Int) -> String? {
        let start = Slot.low(slot)
        let length = Slot.payload(slot)
        return start + length <= sourceCount ? nil : "range \(start)+\(length) past the source (\(sourceCount) bytes)"
    }
}
