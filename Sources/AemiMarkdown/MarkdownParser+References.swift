extension MarkdownParser {
    /// Takes the link reference definitions off the start of the open paragraph at `index`, records them, and leaves the lines after them.
    mutating func resolveReferenceDefinitions(in index: Int) {
        let consumed = consumeDefinitions(
            firstLine: state.open[index].firstLine, lineCount: state.open[index].lineCount)
        state.open[index].firstLine += consumed
        state.open[index].lineCount -= consumed
    }

    /// The same for a paragraph that is closing. When the definitions use every line, the paragraph disappears (its slot is the last on the tape).
    mutating func resolveReferenceDefinitionsAtClose(_ block: BlockState.Open) {
        let consumed = consumeDefinitions(firstLine: block.firstLine, lineCount: block.lineCount)
        if consumed >= block.lineCount, block.slot == blocks.count - 1 {
            blocks.removeLast()
            return
        }
        state.pending.append(
            .init(slot: block.slot, firstLine: block.firstLine + consumed, lineCount: block.lineCount - consumed))
    }

    /// Parses definitions from the start of the lines and returns how many lines they used.
    private mutating func consumeDefinitions(firstLine: Int, lineCount: Int) -> Int {
        // A definition starts with `[`; most paragraphs do not, and need no scratch text at all.
        guard lineCount > 0, source[state.lineRanges[firstLine].lowerBound] == UInt8(ascii: "[") else { return 0 }
        var text = ContiguousArray<UInt8>()
        var scratchStarts: [Int] = []
        var sourceStarts: [Int] = []
        for line in 0 ..< lineCount {
            let range = state.lineRanges[firstLine + line]
            scratchStarts.append(text.count)
            sourceStarts.append(range.lowerBound)
            text.append(contentsOf: source[range])
            if line + 1 < lineCount { text.append(0x0A) }
        }
        func sourceOffset(_ index: Int) -> Int {
            var line = 0
            while line + 1 < scratchStarts.count, scratchStarts[line + 1] <= index { line += 1 }
            return sourceStarts[line] + index - scratchStarts[line]
        }
        var position = 0
        while position < text.count, let definition = Self.definition(text, &position) {
            let destination =
                sourceOffset(definition.destination.lowerBound) ..< sourceOffset(definition.destination.lowerBound)
                + definition.destination.count
            var title: Range<Int>?
            if let found = definition.title {
                let lower = sourceOffset(found.lowerBound)
                title = lower ..< (lower + found.count)
            }
            references.insert(label: text[definition.label], .init(destination: destination, title: title))
        }
        // Lines used: the line feeds before `position`, and the last line too if every line was used.
        var used = 0
        for index in 0 ..< position where text[index] == 0x0A { used += 1 }
        return position >= text.count ? lineCount : Swift.min(used, lineCount)
    }

    /// One definition at `position`: `[label]: destination "title"`, ending at a line end. The position moves past it (and its line ending) when it parses.
    private static func definition(
        _ text: ContiguousArray<UInt8>, _ position: inout Int
    ) -> (label: Range<Int>, destination: Range<Int>, title: Range<Int>?)? {
        var cursor = position
        let labelStart = cursor
        let labelLength = LinkSyntax.labelLength(text, &cursor)
        guard labelLength >= 3, cursor < text.count, text[cursor] == UInt8(ascii: ":") else { return nil }
        let label = (labelStart + 1) ..< (labelStart + labelLength - 1)
        guard text[label].contains(where: { !ASCIIClass.isWhitespace($0) }) else { return nil }
        cursor += 1
        LinkSyntax.skipSpaceAndOneNewline(text, &cursor)
        let bracketed = cursor < text.count && text[cursor] == UInt8(ascii: "<")
        guard let destination = LinkSyntax.destination(text, &cursor), bracketed || !destination.isEmpty else {
            return nil
        }
        let afterDestination = cursor
        var title: Range<Int>?
        var afterTitle = cursor
        LinkSyntax.skipSpaceAndOneNewline(text, &afterTitle)
        if afterTitle > afterDestination, let found = LinkSyntax.title(text, &afterTitle) {
            title = found
            cursor = afterTitle
        }
        if title != nil, !endLine(text, &cursor) {
            // Something follows the title on its line: the title is not one, and the definition ends after the destination if the line does.
            title = nil
            cursor = afterDestination
        }
        if title == nil, !endLine(text, &cursor) { return nil }
        position = cursor
        return (label, destination, title)
    }

    /// Skips spaces and tabs and one line ending; false if something else follows.
    private static func endLine(_ text: ContiguousArray<UInt8>, _ position: inout Int) -> Bool {
        var index = position
        while index < text.count, text[index] == 0x20 || text[index] == 0x09 { index += 1 }
        if index < text.count {
            guard text[index] == 0x0A else { return false }
            index += 1
        }
        position = index
        return true
    }
}
