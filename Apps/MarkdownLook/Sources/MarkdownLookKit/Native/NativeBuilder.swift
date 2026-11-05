internal import AemiLexers
public import AemiMarkdown
internal import AemiMermaidLayout
internal import AemiMermaidScene
internal import AemiMermaidSyntax
internal import Foundation
internal import SwiftUI

extension NativeDocument {
    /// Reads `document` into rows in one pass, with an explicit stack of the open containers.
    public init(_ document: MarkdownDocument, settings: ViewerSettings = ViewerSettings()) {
        var builder = NativeBuilder(document: document, settings: settings)
        for event in document.events { builder.handle(event) }
        self = builder.finish()
    }
}

/// One open container.
private struct Frame {
    enum Kind {
        case quote(NativeAlert?)
        case list(ordered: Bool, tight: Bool, parenthesis: Bool, depth: Int)
        case item
        case note
    }

    var kind: Kind
    /// For a list, the number of its next item.
    var number = 1
    /// For an item or a note, the marker it takes on its first row, and whether it has.
    var marker: NativeMarker?
    var markerUsed = false
    /// For a quote, whether a row has been put in it.
    var hasRows = false
    /// The space above the first row inside this container, if it is not the first thing in its parent.
    var gapForFirst: NativeGap?
    var label = ""
    var firstRowPending = false
}

struct NativeBuilder {
    private let document: MarkdownDocument
    let settings: ViewerSettings
    private var result = NativeDocument()
    private var frames: [Frame] = []
    /// A block ended since the last row: the next row at the same level is separated from it.
    private var separated = false
    private var previous: Previous?
    private var inline: NativeInline?
    private var leafKind: NodeKind?
    private var leafPayload = 0
    var code: CodeState?
    var table: TableState?
    private var cell: NativeInline?
    private var inNotes = false

    enum Previous { case prose, heading, box, rule }

    struct CodeState {
        var isHTML: Bool
        var language = ""
        var lines: [String] = []
        var pendingSpaces = 0
    }

    struct TableState {
        var alignments: [NativeTable.Alignment] = []
        var header: [AttributedString] = []
        var rows: [[AttributedString]] = []
        var current: [AttributedString] = []
        var isHeader = false
    }

    init(document: MarkdownDocument, settings: ViewerSettings) {
        self.document = document
        self.settings = settings
    }

    mutating func finish() -> NativeDocument { result }

    /// A document that is one diagram (a Mermaid file): its row, or its source as code when the engine does not draw it.
    static func diagramDocument(_ source: String, settings: ViewerSettings) -> NativeDocument {
        var document = NativeDocument()
        let content: NativeContent
        if settings.drawsDiagrams, let diagram = diagram(source) {
            content = .diagram(diagram)
        } else {
            let builder = NativeBuilder(document: MarkdownParser.parse([]), settings: settings)
            content = .code(
                NativeCode(
                    language: "",
                    raw: source,
                    shown: builder.shown(source, language: "", isHTML: true),
                    isHTML: true
                )
            )
        }
        document.rows = [NativeRow(id: 0, guides: [], gap: .none, content: content)]
        return document
    }

    mutating func handle(_ event: MarkdownEvent) {
        switch event {
            case .enter(let node): enter(node)
            case .exit(let node): exit(node)
            case .leaf(let node): leaf(node)
        }
    }

    // MARK: Events

    private mutating func enter(_ node: MarkdownNode) {
        if inline != nil || cell != nil {
            if cell != nil { cell?.enter(node) } else { inline?.enter(node) }
            return
        }
        switch node.kind {
            case .paragraph, .heading:
                inline = NativeInline(smartPunctuation: settings.smartPunctuation)
                leafKind = node.kind
                leafPayload = node.payload
            case .blockQuote: enterQuote(alert: NativeAlert(rawValue: node.payload))
            case .list:
                let flags = ListFlags(rawValue: node.payload)
                let depth = frames.count { if case .list(let ordered, _, _, _) = $0.kind { !ordered } else { false } }
                var frame = Frame(
                    kind: .list(
                        ordered: flags.contains(.ordered),
                        tight: flags.contains(.tight),
                        parenthesis: flags.contains(.parenthesis),
                        depth: depth
                    )
                )
                frame.gapForFirst = containerGap(parentIsTight: innermostTightList)
                frames.append(frame)
                separated = false
            case .listItem: enterItem()
            case .footnoteDefinition: enterNote()
            case .codeBlock, .htmlBlock: code = CodeState(isHTML: node.kind == .htmlBlock)
            case .table: table = TableState(alignments: [])
            case .tableRow: table?.isHeader = node.payload == 1
            case .tableCell:
                cell = NativeInline(smartPunctuation: settings.smartPunctuation)
                // The columns are the header row's cells.
                let aligned = alignment(node.payload)
                if table?.isHeader == true { table?.alignments.append(aligned) }
            default: break
        }
    }

    private mutating func exit(_ node: MarkdownNode) {
        if inline != nil || cell != nil, node.kind != .paragraph, node.kind != .heading, node.kind != .tableCell {
            if cell != nil { cell?.exit(node) } else { inline?.exit(node) }
            return
        }
        switch node.kind {
            case .paragraph, .heading:
                guard let finished = inline else { return }
                inline = nil
                emitText(
                    finished,
                    style: node.kind == .heading ? .heading(Swift.min(6, Swift.max(1, node.payload))) : .body
                )
            case .tableCell:
                if let finished = cell, var state = table {
                    if state.isHeader {
                        state.header.append(finished.string)
                    } else {
                        state.current.append(finished.string)
                    }
                    table = state
                }
                cell = nil
            case .tableRow:
                if var state = table {
                    if !state.isHeader { state.rows.append(state.current) }
                    state.current = []
                    table = state
                }
            case .table: exitTable()
            case .codeBlock, .htmlBlock: exitCode()
            case .blockQuote, .list: closeContainer()
            case .listItem:
                closeContainer()
                if let list = frames.indices.last, case .list = frames[list].kind { frames[list].number += 1 }
            case .footnoteDefinition: exitNote()
            default: break
        }
    }

    private mutating func leaf(_ node: MarkdownNode) {
        let document = self.document
        if cell != nil {
            cell?.leaf(node, in: document)
            return
        }
        if inline != nil {
            if node.kind == .taskMarker { setTask(done: node.payload == 1) } else { inline?.leaf(node, in: document) }
            return
        }
        switch node.kind {
            case .thematicBreak: emit(.rule, kind: .rule)
            case .listStart:
                if let list = frames.indices.last, case .list = frames[list].kind { frames[list].number = node.value }
            case .footnoteLabel:
                let label = String(decoding: document.source[node.range], as: UTF8.self)
                if let note = frames.indices.last {
                    frames[note].label = label
                    frames[note].marker = .note(label)
                }
            case .infoString:
                let word = document.source[node.range].prefix { $0 != 0x20 && $0 != 0x09 }
                let language = String(decoding: document.decode(word.startIndex ..< word.endIndex), as: UTF8.self)
                code?.language = language
            case .virtualSpaces: code?.pendingSpaces = node.value
            case .codeLine:
                let spaces = code?.pendingSpaces ?? 0
                let line =
                    String(repeating: " ", count: spaces) + String(decoding: document.source[node.range], as: UTF8.self)
                code?.lines.append(line)
                code?.pendingSpaces = 0
            default: break
        }
    }

    // MARK: Containers

    private var innermostTightList: Bool {
        for frame in frames.reversed() { if case .list(_, let tight, _, _) = frame.kind { return tight } }
        return false
    }

    /// The space above the first row of a container that follows something at its level.
    private func containerGap(parentIsTight: Bool) -> NativeGap? {
        separated ? (parentIsTight ? .small : .normal) : nil
    }

    private mutating func enterQuote(alert: NativeAlert?) {
        var frame = Frame(kind: .quote(alert))
        frame.gapForFirst = separated ? .box : nil
        frames.append(frame)
        separated = false
        if let alert { emitText(titleText(alert), style: .alertTitle) }
    }

    private func titleText(_ alert: NativeAlert) -> NativeInline {
        var title = NativeInline(smartPunctuation: false)
        title.appendPlain(alert.title)
        return title
    }

    private mutating func enterItem() {
        var tight = false
        if let list = frames.last, case .list(let ordered, let isTight, let parenthesis, let depth) = list.kind {
            tight = isTight
            var item = Frame(kind: .item)
            item.gapForFirst = separated ? (tight ? .small : .normal) : nil
            let number = list.number
            item.marker = ordered ? .number("\(number)\(parenthesis ? ")" : ".")") : .bullet(depth: depth)
            frames.append(item)
        } else {
            frames.append(Frame(kind: .item))
        }
        separated = false
    }

    private mutating func enterNote() {
        var note = Frame(kind: .note)
        let top = frames.isEmpty
        if top, !inNotes {
            inNotes = true
            emit(.footnoteRule, kind: .rule)
            separated = false
        }
        note.gapForFirst = top && previous != .rule ? .small : nil
        note.firstRowPending = true
        frames.append(note)
        separated = false
    }

    private mutating func exitNote() {
        guard let note = frames.last else { return }
        if result.referenceRow[note.label] != nil, let last = result.rows.indices.last,
            case .text(var text) = result.rows[last].content
        {
            text.string.append(AttributedString(" "))
            var back = AttributedString("\u{21A9}\u{FE0E}")
            back.link = NativeLink.url(NativeLink.reference, label: note.label)
            back.foregroundColor = .secondary
            text.string.append(back)
            result.rows[last].content = .text(text)
        }
        closeContainer()
    }

    private mutating func closeContainer() {
        if !frames.isEmpty { frames.removeLast() }
        separated = true
        if frames.isEmpty { inNotesIfNeeded() }
    }

    private mutating func inNotesIfNeeded() {}

    private mutating func setTask(done: Bool) {
        if let item = frames.lastIndex(where: { if case .item = $0.kind { true } else { false } }),
            !frames[item].markerUsed
        {
            frames[item].marker = .task(done: done)
        }
    }

    // MARK: Rows

    private func alignment(_ payload: Int) -> NativeTable.Alignment {
        payload == 2 ? .center : (payload == 3 ? .trailing : .leading)
    }

    private mutating func emitText(_ text: NativeInline, style: NativeText.Style) {
        var inline = text
        var style = style
        if style == .body, frames.contains(where: { if case .note = $0.kind { true } else { false } }) { style = .note }
        // A task marker with nothing after it, or an empty paragraph: nothing to show, but the marker still counts as used by the row.
        if inline.isEmpty, style == .body { inline.appendPlain("") }
        for label in inline.notes where result.referenceRow[label] == nil { pendingReferences.append(label) }
        let kind: Previous = if case .heading = style { .heading } else { .prose }
        emit(.text(NativeText(string: inline.string, style: style)), kind: kind)
    }

    private var pendingReferences: [String] = []

    /// Puts a row in the document: its guides from the open containers, and the space above it from what came before.
    mutating func emit(_ content: NativeContent, kind: Previous) {
        var guides: [NativeGuide] = []
        var strongest: NativeGap?
        for index in frames.indices {
            switch frames[index].kind {
                case .quote(let alert):
                    guides.append(.bar(alert, continues: frames[index].hasRows))
                    frames[index].hasRows = true
                case .item, .note:
                    if frames[index].markerUsed {
                        guides.append(.indent)
                    } else {
                        guides.append(.marker(frames[index].marker ?? .bullet(depth: 0)))
                        frames[index].markerUsed = true
                    }
                case .list: break
            }
            if let first = frames[index].gapForFirst {
                if strongest == nil || first.em > strongest?.em ?? 0 { strongest = first }
                frames[index].gapForFirst = nil
            }
        }
        var gap: NativeGap = .none
        if previous != nil {
            gap = strongest ?? (separated ? .normal : .none)
            if gap != .none { gap = adjust(gap, this: kind) }
        }
        let id = result.rows.count
        result.rows.append(NativeRow(id: id, guides: guides, gap: gap, content: content))
        for label in pendingReferences where result.referenceRow[label] == nil { result.referenceRow[label] = id }
        pendingReferences = []
        if let note = frames.lastIndex(where: { if case .note = $0.kind { true } else { false } }),
            frames[note].firstRowPending
        {
            frames[note].firstRowPending = false
            result.noteRow[frames[note].label] = id
        }
        previous = kind
        separated = true
    }

    /// The step the kinds on either side ask for: under a heading, above one, around a box or a rule.
    private func adjust(_ gap: NativeGap, this: Previous) -> NativeGap {
        if previous == .heading { return .heading }
        if this == .heading || this == .rule || previous == .rule { return .section }
        if this == .box || previous == .box { return gap.em < NativeGap.box.em ? .box : gap }
        return gap
    }
}
