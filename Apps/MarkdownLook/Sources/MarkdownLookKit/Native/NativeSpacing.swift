/// What a block follows among its siblings, for the space above it.
enum Sibling: Equatable {
    case prose
    case heading(Int)
    /// Code, a diagram, a table, a quote, an alert: what the page's style sheet sets apart with the space of a box.
    case box
    case rule
    case list
    case item
    /// The short rule above the notes.
    case notes
    /// An alert's title.
    case title

    var isBox: Bool { self == .box }
    var isSection: Bool { self == .rule || self == .notes }
}

/// The space above a block, as the style sheet of the page (`ViewerStyle`) decides it, in the order of the cascade: the step between blocks (1 em), under a heading (0.6) and above one (2.2), in a
/// list that comes under its item (the item step), around a box (1.5) and a section (2.2), and in a tight item or under an alert's title (0.4). A later step wins over an earlier one, as a
/// selector of more weight does. The result is in em of the body text: the space is in em of the block's own font, so above a heading it is of the heading's size.
enum Spacing {
    /// The scale of the style sheet.
    static let gap = 1.0, small = 0.4, box = 1.5, section = 2.2, head = 0.6
    static let notesScale = 0.92
    static let headingScales = [1.9, 1.45, 1.15, 1, 1, 1]

    /// Where a block sits: in a tight item, where its children are `small` apart; in a list, where the children are items; among the notes.
    struct Flow {
        var tight = false
        var inItem = false
    }

    static func margin(after previous: Sibling?, this: Sibling, flow: Flow, itemStep: Double) -> Double {
        guard let previous else { return 0 }
        if this == .item { return itemStep }
        var value = gap
        if case .heading = previous { value = head }
        if case .heading = this { value = section }
        if this == .list, flow.inItem { value = itemStep }
        if this.isBox || previous.isBox { value = box }
        if this.isSection || previous.isSection { value = section }
        if flow.tight { value = small }
        if previous == .title { value = small }
        return value * scale(this)
    }

    /// The size of a block's own font in em of the body.
    static func scale(_ sibling: Sibling) -> Double {
        switch sibling {
            case .heading(let level): headingScales[Swift.min(6, Swift.max(1, level)) - 1]
            case .notes: notesScale
            default: 1
        }
    }
}
