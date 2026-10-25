@testable import AemiMarkdown

/// What GitHub's HTML output keeps about footnotes: which labels were referenced, in what order, how many times, and the events of each definition (which are not
/// written where they stand, but in a section at the end).
struct FootnoteBook {
    private(set) var order: [[UInt8]] = []
    private(set) var references: [[UInt8]: Int] = [:]
    private(set) var definitions: [[UInt8]: [MarkdownEvent]] = [:]
    private var capturing: (label: [UInt8], depth: Int, events: [MarkdownEvent])?

    /// Takes `event` if it belongs to a definition, true if so. A definition starts at its `enter` event, and its label leaf names it.
    mutating func capture(_ event: MarkdownEvent) -> Bool {
        if var current = capturing {
            switch event {
                case .enter: current.depth += 1
                case .exit: current.depth -= 1
                case .leaf: break
            }
            if current.depth == 0 {
                definitions[current.label] = current.events
                capturing = nil
            } else {
                current.events.append(event)
                capturing = current
            }
            return true
        }
        if case .enter(let node) = event, node.kind == .footnoteDefinition {
            capturing = ([], 1, [])
            return true
        }
        return false
    }

    /// The label a definition declares: the label leaf is its first event, so the key is set from it.
    mutating func name(_ label: [UInt8]) {
        if var current = capturing, current.label.isEmpty {
            current.label = label
            capturing = current
        }
    }

    /// The number of the footnote (counted from 1, in the order of first reference) and the number of this reference to it, 1 for the first.
    mutating func reference(_ label: [UInt8]) -> (number: Int, occurrence: Int) {
        if references[label] == nil { order.append(label) }
        references[label, default: 0] += 1
        return (order.firstIndex(of: label)! + 1, references[label]!)
    }
}
