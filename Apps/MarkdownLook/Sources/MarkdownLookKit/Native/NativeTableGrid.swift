internal import AppKit
public import SwiftUI

/// How the page sizes a table's columns, read from the cells: the same measure the HTML writer takes (`TableLayout`, ADR 0004), so a column that stays on a line there stays on a line here, and a
/// table that takes the room beside the text column there takes it here.
@available(macOS 26.0, *)
struct NativeTableShape {
    let layout: TableLayout
    let columns: Int

    init(_ table: NativeTable) {
        var layout = TableLayout()
        columns = table.header.count
        layout.columns = Array(repeating: TableLayout.Column(), count: columns)
        for row in [table.header] + table.rows {
            for (index, cell) in row.enumerated() where index < columns {
                let (length, word) = Self.measure(cell)
                layout.columns[index].longest = Swift.max(layout.columns[index].longest, length)
                layout.columns[index].longestWord = Swift.max(layout.columns[index].longestWord, word)
            }
        }
        self.layout = layout
    }

    var isWide: Bool { layout.isWide }

    /// Whether a column keeps its text on one line.
    func keepsLine(_ column: Int) -> Bool { layout.columns[column].longest <= layout.fitLimit }

    /// The narrowest a column that wraps is made, in characters: its longest word, between 12 and 28.
    func floor(_ column: Int) -> Int {
        Swift.min(TableLayout.flexibleCeiling, Swift.max(TableLayout.flexibleFloor, layout.columns[column].longestWord))
    }

    /// The width of the longest piece of a cell that a line cannot break: the text between spaces and after hyphens, in the fonts the cell sets it in.
    static func unbreakable(
        _ cell: AttributedString,
        size: CGFloat,
        codeScale: CGFloat,
        weight: NSFont.Weight,
        fonts: NativeFonts = NativeFonts()
    )
        -> CGFloat
    {
        var current: CGFloat = 0
        var best: CGFloat = 0
        func width(_ piece: String, _ font: NSFont) -> CGFloat {
            (piece as NSString).size(withAttributes: [.font: font]).width
        }
        for run in cell.runs {
            let intent = run.inlinePresentationIntent ?? []
            let isCode = intent.contains(.code)
            let font =
                isCode
                ? fonts.nsFont(.code, size: size * codeScale)
                : fonts.nsFont(.text, size: size, weight: intent.contains(.stronglyEmphasized) ? .semibold : weight)
            let edge = isCode ? size * codeScale * 0.3 : 0
            current += edge
            var piece = ""
            for character in String(cell[run.range].characters) {
                if character == " " || character == "\n" {
                    current += width(piece, font)
                    best = Swift.max(best, current)
                    current = 0
                    piece = ""
                } else {
                    piece.append(character)
                    if character == "-" {
                        current += width(piece, font)
                        best = Swift.max(best, current)
                        current = 0
                        piece = ""
                    }
                }
            }
            current += width(piece, font) + edge
        }
        return Swift.max(best, current)
    }

    /// The characters of a cell and the longest word in it, a line break counting as a space.
    static func measure(_ cell: AttributedString) -> (length: Int, word: Int) {
        var length = 0
        var word = 0
        var current = 0
        for character in cell.characters {
            length += 1
            if character == " " || character == "\n" {
                current = 0
            } else {
                current += 1
                word = Swift.max(word, current)
            }
        }
        return (length, word)
    }
}

/// Columns sized as a browser sizes an automatic table: each as wide as its text if the table fits; else down towards its narrowest (the longest word, or the whole text where the line is kept), the
/// room shared in proportion to what each can give up; and rows as tall as their tallest cell at that width. The cells are in row order, `columns` to a row, the first row the header.
/// What a cell's text cannot be narrowed below, with its padding.
@available(macOS 26.0, *)
struct UnbreakableWidth: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

@available(macOS 26.0, *)
struct NativeTableGrid: Layout {
    let columns: Int
    /// A column that keeps its text on one line.
    let keeps: [Bool]
    /// The narrowest width of a column that wraps, with its padding.
    let floors: [CGFloat]
    /// The room the table may take, or nil for as much as its text.
    let available: CGFloat?

    struct Cache {
        var ideal: [CGFloat] = []
        var least: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        var cache = Cache()
        for subview in subviews {
            cache.ideal.append(subview.sizeThatFits(.unspecified).width)
            cache.least.append(subview[UnbreakableWidth.self])
        }
        return cache
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = makeCache(subviews: subviews) }

    /// The width of each column.
    func widths(_ cache: Cache) -> [CGFloat] {
        var most = [CGFloat](repeating: 0, count: columns)
        var least = [CGFloat](repeating: 0, count: columns)
        for (index, ideal) in cache.ideal.enumerated() {
            let column = index % columns
            let header = index < columns
            let narrowest = header || keeps[column] ? ideal : Swift.max(cache.least[index], floors[column])
            least[column] = Swift.max(least[column], narrowest)
            most[column] = Swift.max(most[column], ideal, narrowest)
        }
        guard let available else { return most }
        let sumMost = most.reduce(0, +)
        if sumMost <= available { return most }
        if least.reduce(0, +) >= available { return least }
        // As the browser's automatic layout shares it (measured against WebKit, ADR 0004): a column that keeps its text on a line is as wide as that; the others each take their share of the whole room in
        // proportion to the width of their text on one line, never less than their narrowest, and the last of them takes what is left.
        var widths = least
        let flexible = (0 ..< columns).filter { most[$0] > least[$0] }
        var left =
            available
            - zip(least, most).enumerated().reduce(0) { $0 + (flexible.contains($1.offset) ? 0 : $1.element.0) }
        for column in flexible.dropLast() {
            widths[column] = Swift.max(least[column], available * most[column] / sumMost)
            left -= widths[column]
        }
        if let last = flexible.last { widths[last] = Swift.max(least[last], left) }
        return widths
    }

    private func heights(_ widths: [CGFloat], _ subviews: Subviews) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns)
            .map { start in
                (0 ..< columns)
                    .reduce(0) { height, column in
                        let fit = subviews[start + column]
                            .sizeThatFits(ProposedViewSize(width: widths[column], height: nil))
                        return Swift.max(height, fit.height)
                    }
            }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard columns > 0, subviews.count >= columns else { return .zero }
        let widths = widths(cache)
        return CGSize(width: widths.reduce(0, +), height: heights(widths, subviews).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard columns > 0, subviews.count >= columns else { return }
        let widths = widths(cache)
        var y = bounds.minY
        for (row, height) in heights(widths, subviews).enumerated() {
            var x = bounds.minX
            for column in 0 ..< columns {
                subviews[row * columns + column]
                    .place(
                        at: CGPoint(x: x, y: y),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(width: widths[column], height: height)
                    )
                x += widths[column]
            }
            y += height
        }
    }
}
