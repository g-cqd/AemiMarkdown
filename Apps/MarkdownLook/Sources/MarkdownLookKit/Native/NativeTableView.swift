internal import SwiftUI

/// A table as the style sheet sets it: a grid in a box that scrolls sideways. The table is 0.96 em and a header cell 0.92 of that, in weight 500 and the secondary colour, lines of 1.45; a cell has
/// 0.6 em above and below and 1.4 em at the sides (none at the outer sides of the first and last column), each in its own em; the rule under every row is inside the row, the header's in the mark colour.
/// Short columns stay on a line, long cells wrap down to a measure.
struct NativeTableView: View {
    let table: NativeTable
    let size: CGFloat
    let settings: ViewerSettings
    @State private var natural: CGFloat = 0

    private var edge: Bool { settings.outerBorder }

    var body: some View {
        ScrollView(.horizontal) {
            grid.fixedSize()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    natural = $0
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay {
            if settings.outerBorder {
                RoundedRectangle(cornerRadius: size * 0.6).strokeBorder(NativeTheme.rule, lineWidth: 1.5)
            }
        }
        .frame(maxWidth: natural > 0 ? natural : nil, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(table.header.indices, id: \.self) {
                    cell(table.header[$0], column: $0, header: true, last: false)
                }
            }
            ForEach(table.rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(table.rows[index].indices, id: \.self) {
                        cell(table.rows[index][$0], column: $0, header: false, last: index == table.rows.count - 1)
                    }
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
            digits: true,
            wraps: !settings.scrollsTables
        )
        .multilineTextAlignment(alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading))
        .frame(maxWidth: settings.scrollsTables ? nil : size * 28, alignment: frameAlignment(alignment))
        .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
        .padding(.vertical, own * 0.6)
        .padding(.leading, column == 0 ? (edge ? side : 0) : side)
        .padding(.trailing, column == columns - 1 ? (edge ? side : 0) : side)
        .overlay(alignment: .bottom) {
            if settings.rowLines { Capsule().fill(header ? NativeTheme.mark : NativeTheme.rule).frame(height: 1.5) }
        }
        .overlay(alignment: .leading) {
            if settings.columnLines, column > 0 { Capsule().fill(NativeTheme.rule).frame(width: 1.5) }
        }
    }

    private func frameAlignment(_ alignment: NativeTable.Alignment) -> Alignment {
        alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading)
    }
}
