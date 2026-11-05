internal import AppKit
internal import SwiftUI

/// A table as the style sheet sets it: a grid in a box that scrolls sideways. The table is 0.96 em and a header cell 0.92 of that, in weight 500 and the secondary colour, lines of 1.45; a cell has
/// 0.6 em above and below and 1.4 em at the sides (none at the outer sides of the first and last column), each in its own em; the rule under every row is inside the row, the header's in the mark colour.
/// Short columns stay on a line, long cells wrap down to a measure.
struct NativeTableView: View {
    let table: NativeTable
    let size: CGFloat
    let settings: ViewerSettings
    /// The table starts at the text's leading edge and scrolls across the whole window: the row is as wide as the window.
    var bleeds = false
    @State private var natural: CGFloat = 0
    @State private var available: CGFloat = 0

    private var edge: Bool { settings.outerBorder }
    private var shape: NativeTableShape { NativeTableShape(table) }
    private var margin: CGFloat { size * 2.5 }
    /// The width of the text column the table sits in, and how far its leading edge is from the window's.
    private var column: CGFloat {
        let room = Swift.max(0, available - 2 * margin)
        return settings.fullWidth ? room : Swift.min(room, size * 40)
    }
    private var lead: CGFloat {
        settings.alignsLeft || settings.fullWidth ? margin : margin + (available - 2 * margin - column) / 2
    }
    /// What the table may take: the column, or the room beside it for a wide table.
    private var room: CGFloat {
        let room = Swift.max(0, available - 2 * margin)
        let cap = settings.fullWidth ? room : Swift.min(room, size * (shape.isWide ? 68 : 40))
        return Swift.max(0, Swift.min(cap, available - lead - margin))
    }

    var body: some View {
        let shape = shape
        if bleeds {
            ScrollView(.horizontal, showsIndicators: false) {
                grid(shape, room: room)
                    .overlay { outline }
                    .padding(.leading, lead)
                    .padding(.trailing, margin)
                    .background(NoBounce())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                available = $0
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                grid(shape, room: available > 0 ? available : nil)
                    .background(NoBounce())
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.width
                    } action: {
                        natural = $0
                    }
            }
            .overlay { outline }
            .frame(maxWidth: natural > 0 ? natural : nil, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: shape.isWide && !settings.alignsLeft ? .center : .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                available = $0
            }
        }
    }

    @ViewBuilder private var outline: some View {
        if settings.outerBorder {
            RoundedRectangle(cornerRadius: size * 0.6).strokeBorder(NativeTheme.rule, lineWidth: 1.5)
        }
    }

    private func grid(_ shape: NativeTableShape, room: CGFloat?) -> some View {
        let own = size * 0.96
        let side = own * 1.4
        let zero = ("0" as NSString)
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: own, weight: .regular)]).width
        let floors = (0 ..< shape.columns)
            .map { column -> CGFloat in
                let pad = (column == 0 && !edge ? 0 : side) + (column == shape.columns - 1 && !edge ? 0 : side)
                return CGFloat(shape.floor(column)) * (zero > 0 ? zero : own * 0.6) + pad
            }
        let keeps = (0 ..< shape.columns).map { settings.scrollsTables || shape.keepsLine($0) }
        return NativeTableGrid(
            columns: shape.columns,
            keeps: keeps,
            floors: floors,
            available: room
        ) {
            ForEach(table.header.indices, id: \.self) { cell(table.header[$0], column: $0, header: true, last: false) }
            ForEach(table.rows.indices, id: \.self) { index in
                ForEach(0 ..< shape.columns, id: \.self) { column in
                    cell(
                        column < table.rows[index].count ? table.rows[index][column] : AttributedString(),
                        column: column,
                        header: false,
                        last: index == table.rows.count - 1
                    )
                }
            }
        }
    }

    private func cell(_ text: AttributedString, column: Int, header: Bool, last: Bool) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        let own = size * 0.96 * (header ? 0.92 : 1)
        let columns = table.header.count
        let side = own * 1.4
        return PageText(
            string: text,
            size: own,
            weight: header ? .medium : .regular,
            color: header ? NativeTheme.secondary : NativeTheme.text,
            lineHeight: own * 1.45,
            codeScale: header ? 0.9 : 0.88,
            digits: true
        )
        .multilineTextAlignment(alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading))
        .padding(.vertical, own * 0.6)
        .padding(.leading, column == 0 ? (edge ? side : 0) : side)
        .padding(.trailing, column == columns - 1 ? (edge ? side : 0) : side)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(alignment, top: true))
        .layoutValue(
            key: UnbreakableWidth.self,
            value: NativeTableShape.unbreakable(
                text,
                size: own,
                codeScale: header ? 0.9 : 0.88,
                weight: header ? .medium : .regular
            ) + (column == 0 ? (edge ? side : 0) : side) + (column == columns - 1 ? (edge ? side : 0) : side)
        )
        .overlay(alignment: .bottom) {
            // With an outline the last row's rule would lie on the outline's bottom edge, so the page leaves it out.
            if settings.rowLines, !(last && edge) {
                Capsule().fill(header ? NativeTheme.mark : NativeTheme.rule).frame(height: 1.5)
            }
        }
        .overlay(alignment: .leading) {
            if settings.columnLines, column > 0 { Capsule().fill(NativeTheme.rule).frame(width: 1.5) }
        }
    }

    private func frameAlignment(_ alignment: NativeTable.Alignment, top: Bool) -> Alignment {
        alignment == .center ? .top : (alignment == .trailing ? .topTrailing : .topLeading)
    }
}
