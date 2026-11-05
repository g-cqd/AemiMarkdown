internal import AemiMarkdown
internal import AppKit
public import SwiftUI

/// A document as a SwiftUI list of rows (ADR 0004): the system font at the chosen size, one scale of space, one indent for every nesting, native text selection, native links and copy buttons.
/// Quick Look's preview is HTML because its reply is; the app and the lab draw this.
public struct NativeDocumentView: View {
    private let document: NativeDocument
    private let settings: ViewerSettings

    public init(document: NativeDocument, settings: ViewerSettings) {
        self.document = document
        self.settings = settings
    }

    public var body: some View {
        let size = CGFloat(settings.textSize)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(document.rows) { row in
                        NativeRowView(row: row, size: size, settings: settings)
                            .frame(maxWidth: settings.fullWidth ? .infinity : size * 40, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .id(row.id)
                    }
                }
                .padding(.horizontal, size * 2.5)
                .padding(.top, size * 3.5)
                .padding(.bottom, size * 5)
                .textSelection(.enabled)
            }
            .tint(Color(nsColor: .linkColor))
            .environment(\.openURL, OpenURLAction { url in open(url, proxy: proxy) })
        }
    }

    /// A footnote link scrolls to its note and a back link to the first reference; a web link opens in the browser; anything else does nothing.
    private func open(_ url: URL, proxy: ScrollViewProxy) -> OpenURLAction.Result {
        if let link = NativeLink.parse(url) {
            let target =
                link.scheme == NativeLink.note ? document.noteRow[link.label] : document.referenceRow[link.label]
            if let target { withAnimation(.smooth) { proxy.scrollTo(target, anchor: .center) } }
            return .handled
        }
        return ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
    }
}

extension NativeRow {
    fileprivate var isTable: Bool { if case .table = content { true } else { false } }
}

/// One row: its guides, then its content, with the space above it.
struct NativeRowView: View {
    let row: NativeRow
    let size: CGFloat
    let settings: ViewerSettings

    private var indent: CGFloat { size * 1.75 }
    private var gap: CGFloat { size * row.gap.em }
    private var lineHeight: CGFloat { size * 1.6 }
    private var isQuote: Bool { row.guides.contains { if case .bar(nil, _) = $0 { true } else { false } } }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(row.guides.enumerated()), id: \.offset) { _, guide in guideView(guide) }
            content.padding(.top, gap)
        }
    }

    @ViewBuilder private func guideView(_ guide: NativeGuide) -> some View {
        switch guide {
            case .bar(let alert, let continues):
                Capsule().fill(alert == nil ? Color.primary.opacity(0.28) : Color.secondary).frame(width: 2)
                    .padding(.top, continues ? 0 : gap).frame(width: indent, alignment: .leading)
                    .frame(maxHeight: .infinity)
            case .marker(let marker):
                markerView(marker).frame(width: indent - size * 0.45, height: lineHeight, alignment: .trailing)
                    .padding(.trailing, size * 0.45).padding(.top, gap)
            case .indent: Color.clear.frame(width: indent, height: 1).padding(.top, gap)
        }
    }

    @ViewBuilder private func markerView(_ marker: NativeMarker) -> some View {
        switch marker {
            case .bullet(let depth):
                // A dot drawn, not a glyph: its size and place do not depend on the font.
                Circle().fill(depth % 2 == 0 ? Color.secondary.opacity(0.7) : Color.clear)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.2))
                    .frame(width: size * 0.38, height: size * 0.38)
            case .number(let number):
                Text(number).font(.system(size: size).monospacedDigit()).foregroundStyle(.tertiary)
            case .task(let done):
                Image(systemName: done ? "checkmark.square" : "square").font(.system(size: size * 0.95))
                    .foregroundStyle(.secondary)
            case .note(let label):
                Text(label).font(.system(size: size * 0.92).monospacedDigit()).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var content: some View {
        switch row.content {
            case .text(let text): textView(text)
            case .code(let code): NativeCodeView(code: code, size: size, settings: settings)
            case .table(let table): NativeTableView(table: table, size: size, settings: settings)
            case .diagram(let diagram): NativeDiagramView(diagram: diagram, size: size)
            case .rule: Capsule().fill(Color.primary.opacity(0.1)).frame(height: 1.5)
            case .footnoteRule:
                Capsule().fill(Color.primary.opacity(0.28)).frame(width: size * 5, height: 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func textView(_ text: NativeText) -> some View {
        let spacing = size * 0.35
        return Text(text.string)
            .font(font(text.style))
            .foregroundStyle(color(text.style))
            .lineSpacing(spacing)
            .textCase(text.style == .alertTitle ? .uppercase : nil)
            .tracking(text.style == .alertTitle ? size * 0.06 : 0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func font(_ style: NativeText.Style) -> Font {
        switch style {
            case .body: .system(size: size)
            case .heading(let level): .system(size: size * [1.9, 1.45, 1.15, 1, 1, 1][level - 1], weight: .semibold)
            case .alertTitle: .system(size: size * 0.85, weight: .medium)
            case .note: .system(size: size * 0.92)
        }
    }

    private func color(_ style: NativeText.Style) -> HierarchicalShapeStyle {
        switch style {
            case .heading(let level): level >= 5 ? .secondary : .primary
            case .alertTitle, .note: .secondary
            case .body: isQuote ? .secondary : .primary
        }
    }
}
