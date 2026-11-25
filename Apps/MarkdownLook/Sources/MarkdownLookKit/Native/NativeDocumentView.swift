internal import AemiMarkdown
internal import AppKit
public import SwiftUI

/// A document as a SwiftUI list of rows (ADR 0004): the system font at the chosen size, one scale of space, one indent for every nesting, native text selection, native links and copy buttons.
/// Quick Look's preview is HTML because its reply is; the app and the lab draw this.
@available(macOS 26.0, *)
public struct NativeDocumentView: View {
    private let document: NativeDocument
    private let settings: ViewerSettings
    private let base: URL?
    private let onLink: ((URL) -> Void)?
    @State private var selection: DocumentSelection
    @State private var pressed = false
    /// The link under the pointer, as the page holds it: what a secondary click's menu is about.
    @State private var pointed: URL?
    /// The height the scroll view shows: the page is at least that tall, so a press below a short document's end still selects.
    @State private var viewport: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.markdownLinkMenu) private var linkMenu

    /// - Parameters:
    ///   - document: the rows.
    ///   - settings: how they look.
    ///   - base: the folder of the document: what its relative pictures and links are under. With none, only pictures with an absolute path show.
    ///   - onLink: takes the links that leave the page (ADR-0010): a web address, or a file of this Mac. With none, a web address
    ///     opens in the browser and a link to a file does nothing, as before.
    public init(
        document: NativeDocument,
        settings: ViewerSettings,
        base: URL? = nil,
        onLink: ((URL) -> Void)? = nil
    ) {
        self.init(
            document: document,
            settings: settings,
            selection: DocumentSelection(document: document),
            base: base,
            onLink: onLink
        )
    }

    /// With the selection it keeps: a test holds it to see what a gesture did.
    init(
        document: NativeDocument,
        settings: ViewerSettings,
        selection: DocumentSelection,
        base: URL? = nil,
        onLink: ((URL) -> Void)? = nil
    ) {
        self.document = document
        self.settings = settings
        self.base = base
        self.onLink = onLink
        _selection = State(initialValue: selection)
    }

    /// What tells a changed document from the same one: its rows' Markdown.
    private var signature: Int { document.rows.map(\.source).hashValue }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                NativeDocumentColumn(document: document, settings: settings, lazy: true)
                    .coordinateSpace(.named(NativeDocumentColumn.space))
                    // A press anywhere on the page selects (the owner, 2026-11-21): in the margins, between blocks and below the
                    // last one, not only on what is drawn.
                    .frame(minHeight: viewport, alignment: .top)
                    .contentShape(Rectangle())
                    .environment(\.documentSelection, selection)
                    .environment(\.documentBase, base)
                    .simultaneousGesture(selecting)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused)
                    .onCopyCommand { selection.text.map { [NSItemProvider(object: $0 as NSString)] } ?? [] }
                    .onCommand(#selector(NSResponder.selectAll(_:))) { selection.selectAll() }
                    .onChange(of: signature) { selection.load(document) }
                    .onContinuousHover(coordinateSpace: .named(NativeDocumentColumn.space)) { phase in
                        guard linkMenu != nil else { return }
                        let link: URL? = if case .active(let point) = phase { selection.link(at: point) } else { nil }
                        if link != pointed { pointed = link }
                    }
                    .contextMenu {
                        if let linkMenu, let pointed, let target = LinkMenuAction.target(of: pointed, base: base) {
                            linkMenu.content(target)
                        }
                    }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                viewport = $0
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .tint(Color(nsColor: .linkColor))
            .environment(\.openURL, OpenURLAction { url in open(url, proxy: proxy) })
        }
    }

    /// A press and a drag across the page select, from where the press was to where the pointer is, across rows.
    private var selecting: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(NativeDocumentColumn.space))
            .onChanged { value in
                if !pressed {
                    pressed = true
                    focused = true
                    selection.press(at: value.startLocation)
                }
                if abs(value.translation.width) + abs(value.translation.height) > 3 {
                    selection.drag(to: value.location)
                }
            }
            .onEnded { _ in pressed = false }
    }

    /// A footnote link scrolls to its note and a back link to the first reference; what leaves the page is the host's when it takes links, else a
    /// web link opens in the browser; anything else does nothing.
    private func open(_ url: URL, proxy: ScrollViewProxy) -> OpenURLAction.Result {
        func scroll(to row: Int?) -> OpenURLAction.Result {
            if let row { withAnimation(.smooth) { proxy.scrollTo(row, anchor: .center) } }
            return .handled
        }
        switch NativeLinkRoute(url, base: base, hostTakesLinks: onLink != nil) {
            case .note(let label): return scroll(to: document.noteRow[label])
            case .reference(let label): return scroll(to: document.referenceRow[label])
            case .host(let target):
                onLink?(target)
                return .handled
            case .system: return .systemAction
            case .nothing: return .discarded
        }
    }
}

@available(macOS 26.0, *)
extension NativeRow {
    /// The width of the row's column in ems: the text's, and for a table wider than that the room beside it.
    fileprivate var measure: CGFloat {
        if guides.isEmpty, case .table(let table) = content, NativeTableShape(table).isWide { return 68 }
        return 40
    }

    /// Whether a table row is as wide as the window: the setting is on and the table is not inside a list or a quote.
    fileprivate func bleeds(_ settings: ViewerSettings) -> Bool {
        settings.bleedsTables && guides.isEmpty && isTable
    }

    fileprivate var isTable: Bool { if case .table = content { true } else { false } }
}

/// One row: its guides, then its content, with the space above it.
@available(macOS 26.0, *)
struct NativeRowView: View {
    let row: NativeRow
    let size: CGFloat
    let settings: ViewerSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.documentSelection) private var selection
    @Environment(\.pageFonts) private var fonts

    private var indent: CGFloat { size * 1.75 }
    private var gap: CGFloat { size * row.gap }
    private var lineHeight: CGFloat { size * 1.6 }
    private var isQuote: Bool { row.guides.contains { if case .bar(nil, _) = $0 { true } else { false } } }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(row.guides.enumerated()), id: \.offset) { _, guide in guideView(guide) }
            content.padding(.top, gap)
                .overlay {
                    if let selection, selection.covers(row: row.id) {
                        Color(nsColor: .selectedTextBackgroundColor).opacity(0.5).allowsHitTesting(false)
                    }
                }
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(NativeDocumentColumn.space))
        } action: { frame in
            selection?.frames[row.id] = frame
        }
    }

    @ViewBuilder private func guideView(_ guide: NativeGuide) -> some View {
        switch guide {
            case .bar(let alert, let continues):
                // The bar of a quote is one rectangle for the whole quote; its rows draw their parts, overlapping a little so no seam shows.
                Rectangle().fill(alert.map(NativeTheme.alert) ?? NativeTheme.mark).frame(width: 1.5)
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
                Text(number).font(fonts.font(.text, size: size).monospacedDigit()).foregroundColor(NativeTheme.tertiary)
            case .task(let done, let offset): NativeCheckbox(done: done, offset: offset, size: size)
            case .note(let label):
                Text(label).font(fonts.font(.text, size: size * 0.92).monospacedDigit())
                    .foregroundColor(NativeTheme.tertiary)
        }
    }

    @ViewBuilder private var content: some View {
        switch row.content {
            case .text(let text): textView(text)
            case .code(let code): NativeCodeView(code: code, size: size, settings: settings)
            case .table(let table):
                NativeTableView(table: table, size: size, settings: settings, bleeds: row.bleeds(settings))
            case .diagram(let diagram): NativeDiagramView(diagram: diagram, size: size)
            case .image(let image):
                NativeImageView(image: image, size: size) {
                    textView(NativeText(string: image.fallback, style: .body))
                }
            case .frontMatter(let panel):
                NativeFrontMatterView(panel: panel, size: size, settings: settings)
            case .details(let details):
                NativeDetailsView(details: details, size: size, settings: settings)
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
            if case .alertTitle(let alert) = text.style {
                // GitHub's icon before the title, in the alert's colour.
                Image(systemName: alert.symbol).font(.system(size: size * scale, weight: .medium))
                    .foregroundStyle(NativeTheme.alert(alert)).padding(.trailing, -size * scale * 0.3)
            }
            PageText(
                string: text.string,
                size: size * scale,
                weight: weight(text.style),
                color: color(text.style),
                lineHeight: size * scale * lineFactor(text.style),
                tracking: size * scale * tracking(text.style),
                balances: isHeading,
                role: isHeading ? .heading : .text,
                row: row.id
            )
            .frame(maxWidth: text.back == nil ? .infinity : nil, alignment: .leading)
            if let label = text.back {
                Spacer(minLength: 0)
                Text("\u{21A9}\u{FE0E}").font(fonts.font(.text, size: size * scale))
                    .foregroundColor(NativeTheme.tertiary)
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
            case .alertTitle: 1
            case .note: Spacing.notesScale
        }
    }

    private func lineFactor(_ style: NativeText.Style) -> Double {
        if case .heading = style { 1.25 } else { 1.6 }
    }

    private func tracking(_ style: NativeText.Style) -> Double {
        switch style {
            case .heading(let level): level == 1 ? -0.02 : -0.012
            default: 0
        }
    }

    private func color(_ style: NativeText.Style) -> Color {
        switch style {
            case .heading(let level): level >= 5 ? NativeTheme.secondary : NativeTheme.text
            case .alertTitle(let alert): NativeTheme.alert(alert)
            case .note: NativeTheme.secondary
            case .body: isQuote ? NativeTheme.secondary : NativeTheme.text
        }
    }
}

/// The rows of a document in a column with the page's padding, with no scroll view around it: what the scroll view holds, and what a snapshot draws.
@available(macOS 26.0, *)
public struct NativeDocumentColumn: View {
    /// The name of the coordinate space the rows report their frames in.
    static let space = "page"

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
        .environment(\.pageFonts, NativeFonts(settings.fonts))
        .padding(.horizontal, size * 2.5)
        .padding(.top, size * 3.5)
        .padding(.bottom, size * 5)
    }

    @ViewBuilder private func rows(_ size: CGFloat) -> some View {
        ForEach(document.rows) { row in
            // One shape of view for every row, whatever it holds. With a branch here (a row as wide as the window, or not), a row
            // that kept its number and changed kind as the text was edited (a diagram that became a table) kept showing what it
            // was: the lazy stack held the view of the other branch under the same id (seen in the lab, 2026-11-14).
            let bleeds = row.bleeds(settings)
            NativeRowView(row: row, size: size, settings: settings)
                .frame(maxWidth: bleeds || settings.fullWidth ? .infinity : size * row.measure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: bleeds || settings.alignsLeft ? .leading : .center)
                // As wide as the window: the column's own padding is taken back, and the table puts it in again where it wants it.
                .padding(.horizontal, bleeds ? -size * 2.5 : 0)
                .id(row.id)
        }
    }
}
