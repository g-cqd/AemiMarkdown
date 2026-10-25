extension InlineParser {
    /// Writes the tree as slots, in document order, into `inlines`. A container's slot learns where its subtree ends when its last child is written.
    ///
    /// No recursion: the containers that are open are a stack of slot indices, and the walk climbs when a node has no next sibling.
    mutating func serialize(into inlines: inout SlotTape) {
        serializeStack.removeAll(keepingCapacity: true)
        var cursor = tree.nodes[0].firstChild
        while cursor >= 0 {
            let node = tree.nodes[Int(cursor)]
            var descended = false
            switch node.kind {
                case .emphasis, .strong, .strikethrough, .codeSpan, .math, .link, .image, .autolink:
                    serializeStack.append((inlines.count, cursor))
                    inlines.append(Slot.make(.container, node.kind, payload: node.payload, low: 0))
                    descended = node.firstChild >= 0
                    if !descended {
                        inlines[serializeStack.removeLast().slot] = Slot.withLow(
                            inlines[inlines.count - 1], inlines.count)
                    }
                case .text:
                    if node.length > 0 {
                        inlines.append(Slot.make(.range, .text, payload: node.length, low: node.start))
                    }
                case .htmlInline, .entity, .linkDestination, .linkTitle, .footnoteReference:
                    inlines.append(Slot.make(.range, node.kind, payload: node.length, low: node.start))
                default:
                    inlines.append(Slot.make(.marker, node.kind, payload: node.payload, low: 0))
            }
            if descended {
                cursor = node.firstChild
                continue
            }
            // Move to the next node, closing each container whose last child this was.
            var next = node.next
            var parent = node.parent
            while next < 0, let top = serializeStack.last, parent == top.node {
                inlines[top.slot] = Slot.withLow(inlines[top.slot], inlines.count)
                serializeStack.removeLast()
                next = tree.nodes[Int(top.node)].next
                parent = tree.nodes[Int(top.node)].parent
            }
            cursor = next
        }
    }
}
