internal import SwiftUI

/// A document's head as the style sheet draws it (`.front-matter`), on the text's own grid: no box and no rules, every line one
/// leading of the text (1.6 em). Closed, one line: its title, its format and how many properties, the chevron hanging in the
/// margin as a list's marker does. Open, a line a property: the key muted at the column's edge (indented a level a nesting), the
/// value on one column, a list of words as words.
struct NativeFrontMatterView: View {
    let panel: FrontMatterPanel
    let size: CGFloat
    @State private var open: Bool
    @Environment(\.pageFonts) private var fonts

    init(panel: FrontMatterPanel, size: CGFloat, startsOpen: Bool) {
        self.panel = panel
        self.size = size
        _open = State(initialValue: startsOpen)
    }

    private var leading: CGFloat { size * 1.6 }
    private var body16: Font { fonts.font(.text, size: size) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if open {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: size * 1.5, verticalSpacing: 0) {
                    ForEach(Array(panel.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            line(Text(row.key), color: NativeTheme.secondary)
                                .padding(.leading, CGFloat(row.depth) * size * 1.75).fixedSize()
                            value(row.value).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Text at the body's size and leading, wrapping at its column's width (a grid row may otherwise get one line's height).
    private func line(_ text: Text, color: Color, weight: Font.Weight = .regular) -> some View {
        text.font(body16.weight(weight)).foregroundColor(color).lineHeight(.exact(points: leading))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.6) {
            if let title = panel.title { line(Text(title), color: NativeTheme.text, weight: .medium).lineLimit(1) }
            line(Text(panel.format), color: NativeTheme.tertiary).fixedSize()
            Spacer(minLength: 0)
            line(Text("\(panel.count) propert\(panel.count == 1 ? "y" : "ies")"), color: NativeTheme.tertiary)
                .fixedSize()
        }
        .overlay(alignment: .leading) {
            Text("\u{203A}").font(body16).foregroundColor(NativeTheme.tertiary).lineHeight(.exact(points: leading))
                .frame(width: size * 0.6).rotationEffect(.degrees(open ? 90 : 0)).offset(x: -size * 1.1)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
    }

    @ViewBuilder private func value(_ value: FrontMatterPanel.Value) -> some View {
        switch value {
            case .text(let text), .date(let text): line(Text(text), color: NativeTheme.text)
            case .link(let address):
                if let url = URL(string: address) {
                    Link(destination: url) { line(Text(address), color: NativeTheme.link) }
                } else {
                    line(Text(address), color: NativeTheme.text)
                }
            case .flag(let flag): line(Text(flag ? "true" : "false"), color: NativeTheme.text)
            case .tags(let tags): line(Text(Self.words(tags)), color: NativeTheme.text)
            case .none: line(Text(""), color: NativeTheme.text)
        }
    }

    /// The words of a list, a muted middle dot between them, bound to the word before it (a narrow no-break space) so a line
    /// breaks after a dot, never before one.
    static func words(_ tags: [String]) -> AttributedString {
        var text = AttributedString()
        for (index, tag) in tags.enumerated() {
            if index > 0 {
                var dot = AttributedString("\u{202F}\u{00B7}\u{2009}")
                dot.foregroundColor = NativeTheme.tertiary
                text += dot
            }
            // An item is kept whole: a line breaks between items only.
            text += AttributedString(tag.replacingOccurrences(of: " ", with: "\u{00A0}"))
        }
        return text
    }
}
