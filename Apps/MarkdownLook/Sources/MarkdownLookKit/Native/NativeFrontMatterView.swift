internal import SwiftUI

/// A document's head as the style sheet draws it (`.front-matter`): a card closed to one line, its format, its title and how many
/// properties, that opens to one row a key; tags as capsules, a flag as a check, a link in the link colour.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if open {
                Rectangle().fill(NativeTheme.rule).frame(height: 1.5)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: size * 1.2, verticalSpacing: size * 0.9) {
                    ForEach(Array(panel.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.key).font(fonts.font(.text, size: size * 0.96))
                                .foregroundColor(NativeTheme.secondary)
                                .padding(.leading, CGFloat(row.depth) * size * 1.75).fixedSize()
                            value(row.value).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, size * 1.1).padding(.vertical, size * 0.7)
            }
        }
        .background(RoundedRectangle(cornerRadius: size * 0.6).fill(NativeTheme.tint))
        .overlay(RoundedRectangle(cornerRadius: size * 0.6).stroke(NativeTheme.rule, lineWidth: 1.5))
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.75) {
            Image(systemName: "chevron.right").font(.system(size: size * 0.7, weight: .semibold))
                .foregroundColor(NativeTheme.tertiary).rotationEffect(.degrees(open ? 90 : 0))
            Text(panel.format).font(fonts.font(.text, size: size * 0.76).weight(.semibold)).tracking(size * 0.05)
                .foregroundColor(NativeTheme.tertiary)
            if let title = panel.title {
                Text(title).font(fonts.font(.text, size: size).weight(.medium)).foregroundColor(NativeTheme.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(panel.count) propert\(panel.count == 1 ? "y" : "ies")").font(fonts.font(.text, size: size * 0.86))
                .foregroundColor(NativeTheme.tertiary)
        }
        .padding(.horizontal, size * 1.1).padding(.vertical, size * 0.6)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
    }

    @ViewBuilder private func value(_ value: FrontMatterPanel.Value) -> some View {
        let body = fonts.font(.text, size: size * 0.96)
        switch value {
            case .text(let text), .date(let text): Text(text).font(body).foregroundColor(NativeTheme.text)
            case .link(let address):
                if let url = URL(string: address) {
                    Link(address, destination: url).font(body).foregroundColor(NativeTheme.link)
                } else {
                    Text(address).font(body)
                }
            case .flag(let flag):
                Text(flag ? "\u{2713}" : "\u{2014}").font(body.weight(flag ? .semibold : .regular))
                    .foregroundColor(flag ? NativeTheme.text : NativeTheme.tertiary)
            case .tags(let tags):
                FlowLayout(spacing: size * 0.3) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        Text(tag).font(fonts.font(.text, size: size * 0.9)).padding(.horizontal, size * 0.6)
                            .padding(.vertical, size * 0.08)
                            .background(Capsule().fill(NativeTheme.tint))
                            .overlay(Capsule().stroke(NativeTheme.rule, lineWidth: 1.5))
                    }
                }
            case .none: EmptyView()
        }
    }
}

/// Subviews in lines, each line as full as the width allows.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(
            width: lines.map(\.width).max() ?? 0,
            height: lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var lines: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = lines.last, last.width + spacing + size.width <= width {
                lines[lines.count - 1].indices.append(index)
                lines[lines.count - 1].width += spacing + size.width
                lines[lines.count - 1].height = max(last.height, size.height)
            } else {
                lines.append(([index], size.width, size.height))
            }
        }
        return lines
    }
}
