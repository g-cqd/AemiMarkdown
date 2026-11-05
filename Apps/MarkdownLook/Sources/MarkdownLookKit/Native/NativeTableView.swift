internal import SwiftUI

/// A table as a grid in a box that scrolls sideways: short columns stay on a line, long cells wrap down to a measure, lines between rows, between columns and around the table by the settings.
struct NativeTableView: View {
    let table: NativeTable
    let size: CGFloat
    let settings: ViewerSettings
    @State private var natural: CGFloat = 0

    private var rule: Color { Color.primary.opacity(0.1) }
    private var mark: Color { Color.primary.opacity(0.28) }
    private var edge: CGFloat { settings.outerBorder ? size * 1.4 : 0 }

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
            if settings.outerBorder { RoundedRectangle(cornerRadius: size * 0.6).strokeBorder(rule, lineWidth: 1.5) }
        }
        .frame(maxWidth: natural > 0 ? natural : nil, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow { ForEach(table.header.indices, id: \.self) { cell(table.header[$0], column: $0, header: true) } }
            line(mark, show: settings.rowLines)
            ForEach(table.rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(table.rows[index].indices, id: \.self) {
                        cell(table.rows[index][$0], column: $0, header: false)
                    }
                }
                if index < table.rows.count - 1 { line(rule, show: settings.rowLines) }
            }
        }
    }

    @ViewBuilder private func line(_ color: Color, show: Bool) -> some View {
        if show {
            Capsule().fill(color).frame(height: 1.5).gridCellColumns(max(1, table.header.count))
        } else {
            Color.clear.frame(height: 0).gridCellColumns(max(1, table.header.count))
        }
    }

    private func cell(_ text: AttributedString, column: Int, header: Bool) -> some View {
        let alignment = column < table.alignments.count ? table.alignments[column] : .leading
        let last = column == table.header.count - 1
        return Text(text)
            .font(.system(size: size * (header ? 0.92 : 0.96), weight: header ? .medium : .regular).monospacedDigit())
            .foregroundStyle(header ? .secondary : .primary)
            .lineSpacing(size * 0.2)
            .multilineTextAlignment(alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading))
            .fixedSize(horizontal: settings.scrollsTables, vertical: true)
            .frame(maxWidth: settings.scrollsTables ? nil : size * 28, alignment: frameAlignment(alignment))
            .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
            .padding(.vertical, size * 0.6)
            .padding(.leading, column == 0 ? edge : size * 1.4)
            .padding(.trailing, last ? edge : size * 1.4)
            .overlay(alignment: .leading) {
                if settings.columnLines, column > 0 { Capsule().fill(rule).frame(width: 1.5) }
            }
    }

    private func frameAlignment(_ alignment: NativeTable.Alignment) -> Alignment {
        alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading)
    }
}
