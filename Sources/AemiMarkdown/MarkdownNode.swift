/// One node as a reader sees it: what it is, its payload, and the source bytes it names.
public struct MarkdownNode: Sendable, Equatable {
    public var kind: NodeKind
    /// The heading level, the list flags, the column count, the alignment, or the link's title flag, by kind.
    public var payload: Int
    /// The source bytes of a leaf that names some (a text run, a code line, a destination); empty for the others.
    public var range: Range<Int>
    /// The number a value leaf carries: a list's start, or the spaces a tab left.
    public var value: Int

    public init(kind: NodeKind, payload: Int = 0, range: Range<Int> = 0 ..< 0, value: Int = 0) {
        self.kind = kind
        self.payload = payload
        self.range = range
        self.value = value
    }

    /// The node a slot describes.
    init(slot: UInt64) {
        let kind = Slot.kind(slot)
        let payload = Slot.payload(slot)
        switch Slot.shape(slot) {
            case .range:
                let start = Slot.low(slot)
                self.init(kind: kind, payload: 0, range: start ..< (start + payload))
            case .marker:
                self.init(kind: kind, payload: payload, value: Slot.low(slot))
            case .container, .leafBlock:
                self.init(kind: kind, payload: payload)
        }
    }
}

/// The flags in the payload of a ``NodeKind/list``.
public struct ListFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let ordered = ListFlags(rawValue: 1 << 0)
    /// No item is separated from the next by a blank line, and no item holds blocks separated by one.
    public static let tight = ListFlags(rawValue: 1 << 1)
    /// An ordered list that numbers with `)`, not `.`.
    public static let parenthesis = ListFlags(rawValue: 1 << 2)
}

/// A step of a walk over a document.
public enum MarkdownEvent: Sendable, Equatable {
    case enter(MarkdownNode)
    case exit(MarkdownNode)
    /// A node with no children.
    case leaf(MarkdownNode)
}
