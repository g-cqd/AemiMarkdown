/// A node of the tree the inline parser builds before it writes the tape. Emphasis and links wrap what was scanned before them, so the tree cannot be
/// written as it is read; the tape is written from it afterwards (ADR-0001).
struct InlineNode {
    var kind: NodeKind
    var payload = 0
    /// The source bytes of a leaf, as an offset and a length.
    var start = 0
    var length = 0
    var parent: Int32 = -1
    var firstChild: Int32 = -1
    var lastChild: Int32 = -1
    var previous: Int32 = -1
    var next: Int32 = -1
    /// The longest chain of containers below this node, for the nesting limit.
    var height: Int32 = 0
}

/// The nodes of one leaf block, in an arena that is reused: after the first few blocks, parsing allocates nothing.
struct InlineTree {
    var nodes: ContiguousArray<InlineNode> = []

    mutating func reset() {
        nodes.removeAll(keepingCapacity: true)
        nodes.append(InlineNode(kind: .paragraph))
    }

    static let root: Int32 = 0

    /// Adds a node as the last child of `parent` and returns its index.
    @discardableResult
    mutating func append(_ node: InlineNode, to parent: Int32 = root) -> Int32 {
        let index = Int32(nodes.count)
        let last = nodes[Int(parent)].lastChild
        var node = node
        node.parent = parent
        node.previous = last
        node.next = -1
        nodes.append(node)
        if last >= 0 { nodes[Int(last)].next = index } else { nodes[Int(parent)].firstChild = index }
        nodes[Int(parent)].lastChild = index
        return index
    }

    mutating func link(_ index: Int32, lastChildOf parent: Int32) {
        let last = nodes[Int(parent)].lastChild
        nodes[Int(index)].parent = parent
        nodes[Int(index)].previous = last
        nodes[Int(index)].next = -1
        if last >= 0 { nodes[Int(last)].next = index } else { nodes[Int(parent)].firstChild = index }
        nodes[Int(parent)].lastChild = index
    }

    /// Takes a node out of its parent's list. Its own children stay with it.
    mutating func unlink(_ index: Int32) {
        let node = nodes[Int(index)]
        if node.previous >= 0 {
            nodes[Int(node.previous)].next = node.next
        } else if node.parent >= 0 {
            nodes[Int(node.parent)].firstChild = node.next
        }
        if node.next >= 0 {
            nodes[Int(node.next)].previous = node.previous
        } else if node.parent >= 0 {
            nodes[Int(node.parent)].lastChild = node.previous
        }
        nodes[Int(index)].parent = -1
        nodes[Int(index)].previous = -1
        nodes[Int(index)].next = -1
    }

    /// Puts an unlinked node right after `anchor`, under the same parent.
    mutating func insert(_ index: Int32, after anchor: Int32) {
        let parent = nodes[Int(anchor)].parent
        let next = nodes[Int(anchor)].next
        nodes[Int(index)].parent = parent
        nodes[Int(index)].previous = anchor
        nodes[Int(index)].next = next
        nodes[Int(anchor)].next = index
        if next >= 0 { nodes[Int(next)].previous = index } else { nodes[Int(parent)].lastChild = index }
    }

    /// The greatest height among the siblings after `node` and before `end` (`-1` for all of them).
    func height(after node: Int32, before end: Int32) -> Int32 {
        var height: Int32 = 0
        var next = nodes[Int(node)].next
        while next != end, next >= 0 {
            height = Swift.max(height, nodes[Int(next)].height)
            next = nodes[Int(next)].next
        }
        return height
    }

    /// Moves the siblings after `node` and before `end` (`-1` for all of them) to the end of `container`'s children, in order.
    mutating func moveSiblings(after node: Int32, before end: Int32, into container: Int32) {
        var next = nodes[Int(node)].next
        while next != end, next >= 0 {
            let following = nodes[Int(next)].next
            unlink(next)
            link(next, lastChildOf: container)
            next = following
        }
    }
}
