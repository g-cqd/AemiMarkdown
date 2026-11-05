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
        ScrollViewReader { proxy in
            ScrollView {
                NativeDocumentColumn(document: document, settings: settings, lazy: true)
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
    @Environment(\.openURL) private var openURL

    private var indent: CGFloat { size * 1.75 }
    private var gap: CGFloat { size * row.gap }
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
                // The bar of a quote is one rectangle for the whole quote; its rows draw their parts, overlapping a little so no seam shows.
                Rectangle().fill(alert == nil ? NativeTheme.mark : NativeTheme.note).frame(width: 1.5)
                    .padding(.top, continues ? 0 : gap).frame(width: indent, alignment: .leading)
                    .frame(maxHeight: .infinity)
            case .marker(let marker): markerGuide(marker)
            case .indent: Color.clear.frame(width: indent, height: 1).padding(.top, gap)
        }
    }

    @ViewBuilder private func markerGuide(_ marker: NativeMarker) -> some View {
        if case .note = marker {
            // A footnote's label is a column of its own, 0.7 em from the note.
            markerView(marker).frame(height: size * 0.92 * lineFactor(.note), alignment: .leading)
                .padding(.trailing, size * 0.92 * 0.7).padding(.top, gap)
        } else {
            // A page puts a marker's right edge a space (0.26 em) before the text of a numbered item, and 0.82 em before it for a bullet, whose disc is 0.35 em across.
            let room = marker.isBullet ? 0.82 : 0.26
            markerView(marker)
                .frame(width: indent - size * room, height: lineHeight, alignment: marker.isTask ? .leading : .trailing)
                .padding(.trailing, size * room).padding(.top, gap)
        }
    }

    @ViewBuilder private func markerView(_ marker: NativeMarker) -> some View {
        switch marker {
            case .bullet(let depth):
                // A dot drawn, not a glyph: its size and place do not depend on the font.
                Circle().fill(depth % 2 == 0 ? NativeTheme.tertiary : Color.clear)
                    .overlay(Circle().strokeBorder(NativeTheme.tertiary, lineWidth: 1))
                    .frame(width: size * 0.35, height: size * 0.35).offset(y: 0.7)
            case .number(let number):
                Text(number).font(.system(size: size).monospacedDigit()).foregroundColor(NativeTheme.tertiary)
            case .task(let done):
                TaskBox(done: done).frame(width: size * 0.95, height: size * 0.95)
            case .note(let label):
                Text(label).font(.system(size: size * 0.92).monospacedDigit()).foregroundColor(NativeTheme.tertiary)
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

    /// A text row as the style sheet draws it: the font in its own em, a line of 1.6 (1.25 for a heading), the letter spacing of a heading and of an alert's title.
    private func textView(_ text: NativeText) -> some View {
        let scale = fontScale(text.style)
        let isHeading = if case .heading = text.style { true } else { false }
        return HStack(alignment: .firstTextBaseline, spacing: size * scale * 0.7) {
            PageText(
                string: text.string,
                size: size * scale,
                weight: weight(text.style),
                color: color(text.style),
                lineHeight: size * scale * lineFactor(text.style),
                tracking: size * scale * tracking(text.style),
                uppercase: text.style == .alertTitle,
                balances: isHeading
            )
            .frame(maxWidth: text.back == nil ? .infinity : nil, alignment: .leading)
            if let label = text.back {
                Spacer(minLength: 0)
                Text("\u{21A9}\u{FE0E}").font(.system(size: size * scale)).foregroundColor(NativeTheme.tertiary)
                    .onTapGesture { if let url = NativeLink.url(NativeLink.reference, label: label) { openURL(url) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weight(_ style: NativeText.Style) -> Font.Weight {
        switch style {
            case .heading: .semibold
            case .alertTitle: .medium
            default: .regular
        }
    }

    private func fontScale(_ style: NativeText.Style) -> Double {
        switch style {
            case .body: 1
            case .heading(let level): Spacing.scale(.heading(level))
            case .alertTitle: 0.85
            case .note: Spacing.notesScale
        }
    }

    private func lineFactor(_ style: NativeText.Style) -> Double {
        if case .heading = style { 1.25 } else { 1.6 }
    }

    private func tracking(_ style: NativeText.Style) -> Double {
        switch style {
            case .heading(let level): level == 1 ? -0.02 : -0.012
            case .alertTitle: 0.06
            default: 0
        }
    }

    private func color(_ style: NativeText.Style) -> Color {
        switch style {
            case .heading(let level): level >= 5 ? NativeTheme.secondary : NativeTheme.text
            case .alertTitle, .note: NativeTheme.secondary
            case .body: isQuote ? NativeTheme.secondary : NativeTheme.text
        }
    }
}

/// The rows of a document in a column with the page's padding, with no scroll view around it: what the scroll view holds, and what a snapshot draws.
public struct NativeDocumentColumn: View {
    let document: NativeDocument
    let settings: ViewerSettings
    let lazy: Bool

    public init(document: NativeDocument, settings: ViewerSettings, lazy: Bool = false) {
        self.document = document
        self.settings = settings
        self.lazy = lazy
    }

    public var body: some View {
        let size = CGFloat(settings.textSize)
        Group {
            if lazy {
                LazyVStack(alignment: .leading, spacing: 0) { rows(size) }
            } else {
                VStack(alignment: .leading, spacing: 0) { rows(size) }
            }
        }
        .padding(.horizontal, size * 2.5)
        .padding(.top, size * 3.5)
        .padding(.bottom, size * 5)
    }

    @ViewBuilder private func rows(_ size: CGFloat) -> some View {
        ForEach(document.rows) { row in
            NativeRowView(row: row, size: size, settings: settings)
                .frame(maxWidth: settings.fullWidth ? .infinity : size * 40, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(row.id)
        }
    }
}
