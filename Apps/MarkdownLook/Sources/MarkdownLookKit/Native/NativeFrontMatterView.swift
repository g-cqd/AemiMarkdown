internal import SwiftUI

/// A document's head as the style sheet draws it (`.front-matter`): an outlined box, the stroke of every line on the page (1.5) and
/// the padding of a code block (1.1 em by 1.3 em) inside it. Closed, one line: its title and how many properties, the chevron at the
/// end. Open, a column of properties on the text's leading (1.6 em), a dimmed key over its value; a nested mapping or list a group
/// that opens and closes, its column indented behind a bar as a quote's is.
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

    /// The stroke of the box, of a quote's bar and of a rule.
    static let stroke: CGFloat = 1.5

    var body: some View {
        let style = PropertyStyle(size: size, fonts: fonts)
        VStack(alignment: .leading, spacing: 0) {
            Disclosure(open: $open, style: style) {
                if let title = panel.title {
                    style.line(Text(title), color: NativeTheme.text, weight: .medium).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    style.line(Text(count), color: NativeTheme.tertiary).fixedSize()
                } else {
                    style.line(Text(count), color: NativeTheme.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if open { NativeProperties(rows: panel.rows, style: style).padding(.top, size * 0.6) }
        }
        // CSS pads inside the border; `strokeBorder` draws inside the frame.
        .padding(.vertical, size * 1.1 + Self.stroke)
        .padding(.horizontal, size * 1.3 + Self.stroke)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: size * 0.6).strokeBorder(NativeTheme.rule, lineWidth: Self.stroke))
    }

    private var count: String { "\(panel.count) propert\(panel.count == 1 ? "y" : "ies")" }

    /// The words of a list, a muted middle dot between them, bound to the word before it (a narrow no-break space) so a line
    /// breaks after a dot, never before one.
    /// `dots`, when the items are in the code face: the text's face for the dots, as the page draws them.
    static func words(_ tags: [String], dots: Font? = nil) -> AttributedString {
        var text = AttributedString()
        for (index, tag) in tags.enumerated() {
            if index > 0 {
                var dot = AttributedString("\u{202F}\u{00B7}\u{2009}")
                dot.foregroundColor = NativeTheme.tertiary
                if let dots { dot.font = dots }
                text += dot
            }
            // An item is kept whole: a line breaks between items only.
            text += AttributedString(tag.replacingOccurrences(of: " ", with: "\u{00A0}"))
        }
        return text
    }
}

/// The text of the panel: the body's size, every line one leading.
struct PropertyStyle {
    let size: CGFloat
    let fonts: NativeFonts

    var leading: CGFloat { size * 1.6 }

    /// Text at `scale` of the body's size and at the body's leading, wrapping at its column's width: a whole number of lines, the
    /// leading split above and below the glyphs as the page splits it.
    func line(_ text: Text, color: Color, weight: Font.Weight = .regular, scale: CGFloat = 1) -> some View {
        let font = fonts.nsFont(.text, size: size * scale, weight: weight == .medium ? .medium : .regular)
        return BalancedLayout(lineHeight: leading) {
            text.font(fonts.font(.text, size: size * scale).weight(weight)).foregroundColor(color)
                .lineHeight(.exact(points: leading)).fixedSize(horizontal: false, vertical: true)
        }
        .offset(y: NativeMetrics.halfLeading(font: font, lineHeight: leading))
    }

    /// A value in the code face, at 0.9 of the body's size (the page's `code`), its baseline where the page puts it: on the text's
    /// strut, as an inline `code` in a line of text is.
    func code(_ text: Text, color: Color) -> some View {
        let own = fonts.nsFont(.code, size: size * 0.9)
        let block = fonts.nsFont(.text, size: size)
        return BalancedLayout(lineHeight: leading) {
            text.font(fonts.font(.code, size: size * 0.9)).foregroundColor(color)
                .lineHeight(.exact(points: leading)).fixedSize(horizontal: false, vertical: true)
        }
        .offset(y: NativeMetrics.shift(own: own, block: block, lineHeight: leading))
    }
}

/// A line that opens and closes what follows it, the chevron at its end.
private struct Disclosure<Label: View>: View {
    @Binding var open: Bool
    let style: PropertyStyle
    /// The label's size, a fraction of the body's: the chevron's too, so the two share a line's metrics.
    var scale: CGFloat = 1
    @ViewBuilder let label: Label

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: style.size * 0.6) {
            label
            style.line(Text("\u{203A}"), color: NativeTheme.tertiary, scale: scale).fixedSize()
                .frame(width: style.size).rotationEffect(.degrees(open ? 90 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
    }
}

/// A column of properties, `--gap-s` apart: a dimmed key over its value, or a group.
private struct NativeProperties: View {
    let rows: [FrontMatterPanel.Row]
    let style: PropertyStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.size * 0.4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.isGroup {
                    NativePropertyGroup(row: row, style: style)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        key(row.key)
                        value(row.value).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func key(_ key: String) -> some View {
        style.line(Text(key), color: NativeTheme.secondary, scale: 0.92)
    }

    @ViewBuilder private func value(_ value: FrontMatterPanel.Value) -> some View {
        switch value {
            case .text(let text), .date(let text): style.line(Text(text), color: NativeTheme.text)
            case .code(let text): style.code(Text(text), color: NativeTheme.text)
            case .link(let address):
                if let url = URL(string: address) {
                    Link(destination: url) { style.line(Text(address), color: NativeTheme.link) }
                } else {
                    style.line(Text(address), color: NativeTheme.text)
                }
            case .flag(let flag): style.code(Text(flag ? "true" : "false"), color: NativeTheme.text)
            case .tags(let tags, false): style.line(Text(NativeFrontMatterView.words(tags)), color: NativeTheme.text)
            case .tags(let tags, true):
                style.code(
                    Text(NativeFrontMatterView.words(tags, dots: style.fonts.font(.text, size: style.size))),
                    color: NativeTheme.text
                )
            case .none: style.line(Text("none"), color: NativeTheme.tertiary)
        }
    }
}

/// A nested mapping or list: its key opens and closes its column, which is indented behind a bar.
private struct NativePropertyGroup: View {
    let row: FrontMatterPanel.Row
    let style: PropertyStyle
    @State private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: style.size * 0.4) {
            Disclosure(open: $open, style: style, scale: 0.92) {
                style.line(Text(row.key), color: NativeTheme.secondary, scale: 0.92)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if open {
                NativeProperties(rows: row.children, style: style)
                    .padding(.leading, style.size * 1.75)
                    .overlay(alignment: .leading) {
                        Capsule().fill(NativeTheme.rule).frame(width: NativeFrontMatterView.stroke)
                    }
            }
        }
    }
}
