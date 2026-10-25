extension MarkdownParser {
    /// Whether a block of `child` can be a child of an open `parent`.
    private static func canContain(_ parent: BlockState.Kind, _ child: BlockState.Kind) -> Bool {
        switch parent {
            case .document, .blockQuote, .item, .footnote: true
            case .list: child == .item
            default: false
        }
    }

    /// Closes every open block above index `container`.
    mutating func closeAbove(_ container: Int) {
        while state.open.count - 1 > container { finalizeTop() }
    }

    /// Opens a block under the open block at index `container` (closing what cannot hold it) and returns its index in the stack.
    mutating func addChild(_ kind: BlockState.Kind, to container: Int, slot: UInt64, startLine: Int? = nil) -> Int {
        closeAbove(container)
        while !Self.canContain(state.open[state.open.count - 1].kind, kind) { finalizeTop() }
        let parent = state.open.count - 1
        // A previous sibling that ends in a blank line makes the list loose, whether it is an item in a list or a block in an item.
        if state.open[parent].hasChild, state.open[parent].lastChildEndsBlank {
            if state.open[parent].kind == .list {
                state.open[parent].loose = true
            } else if state.open[parent].kind == .item, state.open[parent - 1].kind == .list {
                state.open[parent - 1].loose = true
            }
        }
        state.open[parent].hasChild = true
        let index = appendBlock(slot)
        state.open.append(BlockState.Open(kind: kind, slot: index, startLine: startLine ?? state.lineNumber))
        return state.open.count - 1
    }

    /// Appends a slot to the block tape and returns its index.
    mutating func appendBlock(_ slot: UInt64) -> Int {
        blocks.append(slot)
        return blocks.count - 1
    }

    private var atContainerLimit: Bool {
        if state.open.count > limits.maxContainerDepth {
            return true
        }
        return false
    }

    /// What trying to start a block on the rest of the line came to.
    private enum Start {
        /// No block starts here.
        case none
        /// A container opened: the rest of the line may start more blocks inside it.
        case container
        /// A block opened (or the line was used up) that takes no further blocks on this line.
        case leaf
    }

    /// cmark's `open_new_blocks`: while the rest of the line starts a block, open it. `container` is the index of the last open block that matched, and
    /// becomes the innermost block opened.
    mutating func startNewBlocks(_ container: inout Int, _ end: Int) {
        // Whether a line indented four columns could still continue the paragraph that is open: not once this line has opened a block of its own.
        var maybeLazy = state.open[state.open.count - 1].kind == .paragraph
        while true {
            let kind = state.open[container].kind
            if kind == .fencedCode || kind == .indentedCode || kind == .htmlBlock { return }
            findFirstNonspace(end)
            let start =
                state.indent >= 4
                ? startIndentedCode(&container, maybeLazy: maybeLazy, end)
                : startUnindented(&container, kind: kind, maybeLazy: maybeLazy, end)
            switch start {
                case .none:
                    _ = tryTable(container: &container, end)
                    return
                case .leaf: return
                case .container: maybeLazy = false
            }
        }
    }

    private mutating func startIndentedCode(_ container: inout Int, maybeLazy: Bool, _ end: Int) -> Start {
        guard !maybeLazy, !state.blank else { return .none }
        advance(4, columns: true, end)
        container = addChild(
            .indentedCode, to: container, slot: Slot.make(.container, .codeBlock, payload: 0, low: 0))
        return .leaf
    }

    /// The starts that need the line to be indented less than four columns, tried in cmark's order.
    private mutating func startUnindented(_ container: inout Int, kind: BlockState.Kind, maybeLazy: Bool, _ end: Int)
        -> Start
    {
        let source = self.source
        let first = peek(state.firstNonspace, end)
        guard state.firstNonspace < end else { return .none }
        if first == UInt8(ascii: ">") { return startQuote(&container, end) }
        if let level = BlockScanner.atxHeadingLevel(source, state.firstNonspace, end) {
            advance(state.firstNonspace + level - state.offset, columns: false, end)
            container = addChild(.heading, to: container, slot: Slot.make(.leafBlock, .heading, payload: level, low: 0))
            return .leaf
        }
        if let fence = BlockScanner.codeFenceOpening(source, state.firstNonspace, end) {
            startFence(&container, fence, end)
            return .leaf
        }
        if first == UInt8(ascii: "<"),
            let condition = HTMLBlockScanner.startCondition(
                source, state.firstNonspace, end, interruptsParagraph: maybeLazy)
        {
            container = addChild(.htmlBlock, to: container, slot: Slot.make(.container, .htmlBlock, payload: 0, low: 0))
            state.open[container].htmlCondition = condition
            return .leaf
        }
        if kind == .paragraph, let level = BlockScanner.setextLevel(source, state.firstNonspace, end) {
            // When definitions use every line of the paragraph, the underline is text: nothing starts here.
            if makeSetextHeading(at: container, level: level) { advance(end - state.offset, columns: false, end) }
            return .leaf
        }
        if first == UInt8(ascii: "["), extensions.contains(.footnotes),
            let label = Self.footnoteLabel(source, state.firstNonspace, end)
        {
            guard !atContainerLimit else { return containerLimitReached() }
            container = openFootnote(label: label, container: container, end)
            return .container
        }
        if BlockScanner.isThematicBreak(source, state.firstNonspace, end) {
            container = addChild(
                .thematicBreak, to: container, slot: Slot.make(.marker, .thematicBreak, payload: 0, low: 0))
            advance(end - state.offset, columns: false, end)
            return .leaf
        }
        if let marker = BlockScanner.listMarker(
            source, state.firstNonspace, end, interruptsParagraph: kind == .paragraph)
        {
            guard !atContainerLimit else { return containerLimitReached() }
            openListItem(marker, container: &container, end)
            return .container
        }
        return .none
    }

    private mutating func startQuote(_ container: inout Int, _ end: Int) -> Start {
        guard !atContainerLimit else { return containerLimitReached() }
        advance(state.firstNonspace + 1 - state.offset, columns: false, end)
        if BlockScanner.isSpaceOrTab(peek(state.offset, end)) { advance(1, columns: true, end) }
        container = addChild(.blockQuote, to: container, slot: Slot.make(.container, .blockQuote, payload: 0, low: 0))
        return .container
    }

    private mutating func startFence(_ container: inout Int, _ fence: (character: UInt8, length: Int), _ end: Int) {
        let fenceOffset = state.firstNonspace - state.offset
        container = addChild(.fencedCode, to: container, slot: Slot.make(.container, .codeBlock, payload: 1, low: 0))
        state.open[container].fenceCharacter = fence.character
        state.open[container].fenceLength = fence.length
        state.open[container].fenceOffset = fenceOffset
        recordInfoString(from: state.firstNonspace + fence.length, end)
        advance(end - state.offset, columns: false, end)
    }

    /// Past the nesting limit a container's marker is text, and nothing more starts on the line.
    private mutating func containerLimitReached() -> Start {
        diagnostics.insert(.containerDepthLimit)
        return .leaf
    }

    /// The info string of a fenced code block: the rest of the opening line, trimmed.
    private mutating func recordInfoString(from start: Int, _ end: Int) {
        var lower = start
        var upper = end
        while lower < upper, BlockScanner.isSpaceOrTab(source[lower]) { lower += 1 }
        while upper > lower, BlockScanner.isSpaceOrTab(source[upper - 1]) { upper -= 1 }
        if upper > lower { blocks.append(Slot.make(.range, .infoString, payload: upper - lower, low: lower)) }
    }

    /// Turns the open paragraph at `index` into a heading of `level`, unless reference definitions use all of its lines.
    private mutating func makeSetextHeading(at index: Int, level: Int) -> Bool {
        resolveReferenceDefinitions(in: index)
        guard state.open[index].lineCount > 0 else { return false }
        openParagraphParser = nil
        openParagraphParsedUpTo = 0
        state.open[index].kind = .heading
        blocks[state.open[index].slot] = Slot.make(.leafBlock, .heading, payload: level, low: 0)
        return true
    }

    /// Opens the list (if the item does not continue the open one) and the list item for `marker`, and positions the cursor after the marker's padding.
    private mutating func openListItem(_ marker: BlockScanner.ListMarker, container: inout Int, _ end: Int) {
        let markerOffset = state.indent
        advance(state.firstNonspace + marker.length - state.offset, columns: false, end)
        let savedOffset = state.offset
        let savedColumn = state.column
        let savedTab = state.partiallyConsumedTab
        while state.column - savedColumn <= 5, BlockScanner.isSpaceOrTab(peek(state.offset, end)) {
            advance(1, columns: true, end)
        }
        let spaces = state.column - savedColumn
        var padding = marker.length + spaces
        if spaces >= 5 || spaces < 1 || state.offset >= end {
            padding = marker.length + 1
            state.offset = savedOffset
            state.column = savedColumn
            state.partiallyConsumedTab = savedTab
            if spaces > 0 { advance(1, columns: true, end) }
        }
        let open = state.open[container]
        if open.kind != .list || open.isOrdered != marker.isOrdered || open.markerCharacter != marker.character {
            var flags: ListFlags = []
            if marker.isOrdered { flags.insert(.ordered) }
            if marker.isOrdered, marker.character == UInt8(ascii: ")") { flags.insert(.parenthesis) }
            container = addChild(
                .list, to: container, slot: Slot.make(.container, .list, payload: flags.rawValue, low: 0))
            state.open[container].isOrdered = marker.isOrdered
            state.open[container].markerCharacter = marker.character
            if marker.isOrdered { blocks.append(Slot.make(.marker, .listStart, payload: 0, low: marker.start)) }
        }
        container = addChild(.item, to: container, slot: Slot.make(.container, .listItem, payload: 0, low: 0))
        state.open[container].markerOffset = markerOffset
        state.open[container].padding = padding
    }
}
