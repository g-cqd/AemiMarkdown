internal import AppKit
internal import Foundation
internal import SwiftUI

/// Marks the text of a code span, so that the renderer below draws a tint behind it.
@available(macOS 26.0, *)
struct CodePill: TextAttribute {}

/// Marks the number of a footnote reference, drawn raised: a raised run in the text itself would push its line's glyphs down, where a page's `line-height: 0` leaves the line alone.
@available(macOS 26.0, *)
struct NoteRaise: TextAttribute {}

/// Marks the text of a link, so that the renderer below draws its underline.
@available(macOS 26.0, *)
struct LinkUnderline: TextAttribute {}

/// Draws a text as SwiftUI would, with what a page adds to it: the rounded tint behind inline code (the rectangle of the run, a font's ascent and descent as an inline box has them, rounded by
/// 0.3 em), and under a link a line one point thick, 0.22 em below the baseline, in the link's colour at 35 %.
@available(macOS 26.0, *)
struct PageTextRenderer: TextRenderer {
    let tint: Color
    let link: Color
    let radius: CGFloat
    let size: CGFloat
    var recorder: SelectionRecorder?
    var raise: CGFloat { size * 0.40 }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        recorder?.capture(layout)
        for line in layout {
            // The runs of one code span (its padding and its text) are one rectangle, drawn under the text.
            var pill: CGRect?
            for run in line {
                if run[CodePill.self] != nil {
                    let rect = run.typographicBounds.rect
                    pill = pill.map { $0.union(rect) } ?? rect
                } else if let rect = pill {
                    fill(rect, in: &context)
                    pill = nil
                }
            }
            if let rect = pill { fill(rect, in: &context) }
            for run in line {
                if run[NoteRaise.self] != nil {
                    var raised = context
                    raised.translateBy(x: 0, y: -raise)
                    raised.draw(run)
                    continue
                }
                context.draw(run)
                if run[LinkUnderline.self] != nil {
                    let bounds = run.typographicBounds
                    let top = bounds.origin.y + size * 0.22
                    context.fill(
                        Path(CGRect(x: bounds.origin.x, y: top, width: bounds.width, height: 1)),
                        with: .color(link.opacity(0.35))
                    )
                }
            }
        }
    }

    private func fill(_ rect: CGRect, in context: inout GraphicsContext) {
        context.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: -radius / 3), cornerRadius: radius), with: .color(tint))
    }
}

/// A text of styled runs as the style sheet sets it: strong at 600, code in 0.9 em of the monospaced font with 0.3 em of room on each side for its tint, a footnote's number at 0.75 em raised,
/// a link in its colour, struck text and a missing image in the secondary one.
@available(macOS 26.0, *)
enum NativeRichText {
    /// The text, and whether it needs the page's renderer.
    static func text(
        _ string: AttributedString,
        size: CGFloat,
        code codeScale: CGFloat = 0.9,
        fonts: NativeFonts = NativeFonts()
    ) -> (
        text: Text, needsRenderer: Bool, map: [Int]
    ) {
        var needsRenderer = false
        // Where each UTF-16 unit of the text as laid out is in the text as written, for a selection: the room a code span or a note's number takes at its sides is at the span's edge.
        var map: [Int] = []
        var written = 0
        var interpolation = LocalizedStringKey.StringInterpolation(
            literalCapacity: 0,
            interpolationCount: string.runs.count
        )
        let spaceWidth = monospacedSpace(fonts)
        for run in string.runs {
            var plain = AttributedString(string[run.range])
            plain.inlinePresentationIntent = nil
            plain.strikethroughStyle = nil
            plain.foregroundColor = nil
            let intent = run.inlinePresentationIntent ?? []
            let isEdged = intent.contains(.code) || (run.link.flatMap(NativeLink.parse)?.scheme == NativeLink.note)
            if isEdged { map.append(written) }
            var inserted: Set<Int> = []
            if intent.contains(.code) { (plain, inserted) = Self.breakableAfterHyphens(plain) }
            for (index, character) in string[run.range].characters.enumerated() {
                for _ in 0 ..< character.utf16.count {
                    map.append(written)
                    written += 1
                }
                if inserted.contains(index) { map.append(written) }
            }
            if isEdged { map.append(written) }
            var piece = Text(plain)
            if intent.contains(.emphasized) { piece = piece.italic() }
            if intent.contains(.stronglyEmphasized) { piece = piece.fontWeight(.semibold) }
            if run.strikethroughStyle != nil { piece = piece.strikethrough(true, color: NativeTheme.secondary) }
            if run.strikethroughStyle != nil || run.foregroundColor != nil {
                piece = piece.foregroundColor(NativeTheme.secondary)
            }
            if let link = run.link {
                let isNote = NativeLink.parse(link)?.scheme == NativeLink.note
                piece = piece.foregroundColor(NativeTheme.link)
                if isNote {
                    let edge = Text("\u{00A0}").font(fonts.font(.code, size: size * 0.75 * 0.1 / spaceWidth))
                    piece = Text("\(edge)\(piece.font(fonts.font(.text, size: size * 0.75)))\(edge)")
                        .customAttribute(NoteRaise())
                    needsRenderer = true
                } else {
                    piece = piece.customAttribute(LinkUnderline())
                    needsRenderer = true
                }
            }
            if intent.contains(.code) {
                let pad = size * codeScale * 0.3
                let edge = Text("\u{00A0}").font(fonts.font(.code, size: pad / spaceWidth))
                piece = piece.font(fonts.font(.code, size: size * codeScale))
                piece = Text("\(edge)\(piece)\(edge)").customAttribute(CodePill())
                needsRenderer = true
            }
            interpolation.appendInterpolation(piece)
        }
        map.append(written)
        return (Text(LocalizedStringKey(stringInterpolation: interpolation)), needsRenderer, map)
    }

    /// A code span breaks as the page breaks it: after a hyphen, which the typesetter takes as no place to break (it falls back to a slash), and not after a slash, which it takes as one.
    private static func breakableAfterHyphens(_ text: AttributedString) -> (AttributedString, Set<Int>) {
        var out = text
        let characters = Array(text.characters)
        var offset = 0
        var inserted: Set<Int> = []
        for index in characters.indices where index + 1 < characters.count {
            let mark: Character
            switch characters[index] {
                case "-": mark = "\u{200B}"
                case "/": mark = "\u{2060}"
                default: continue
            }
            guard characters[index + 1].isLetter || characters[index + 1].isNumber else { continue }
            let at = out.index(out.startIndex, offsetByCharacters: index + 1 + offset)
            out.characters.insert(mark, at: at)
            inserted.insert(index)
            offset += 1
        }
        return (out, inserted)
    }

    /// The width of a space of the monospaced font, in ems: the room a code span's side padding is made of (a space of a smaller font than the code's, so that the line's height does not change).
    private static func monospacedSpace(_ fonts: NativeFonts) -> CGFloat {
        let font = fonts.nsFont(.code, size: 100)
        return NSAttributedString(string: "\u{00A0}", attributes: [.font: font]).size().width / 100
    }
}

/// A run of text as the style sheet sets it: the font at its size and weight, a line of an exact height (the half leading above the glyphs, as a page has it), a whole number of lines, a heading's
/// balance and letter spacing, and the code, links and notes of `NativeRichText`.
@available(macOS 26.0, *)
struct PageText: View {
    let string: AttributedString
    let size: CGFloat
    var weight: Font.Weight = .regular
    var color: Color = NativeTheme.text
    var lineHeight: CGFloat
    var tracking: CGFloat = 0
    var codeScale: CGFloat = 0.9
    var uppercase = false
    var balances = false
    var digits = false
    var wraps = true
    var role = FontRole.text
    /// The row of the document this text is, if it can be selected.
    var row: Int?
    @Environment(\.documentSelection) private var selection
    @Environment(\.pageFonts) private var fonts

    var body: some View {
        let rich = NativeRichText.text(string, size: size, code: codeScale, fonts: fonts)
        var font = fonts.font(role, size: size, weight: weight)
        if digits { font = font.monospacedDigit() }
        let line = rich.text.font(font).foregroundColor(color).lineHeight(.exact(points: lineHeight))
            .textCase(uppercase ? .uppercase : nil).tracking(tracking).fixedSize(horizontal: !wraps, vertical: true)
        var layout = BalancedLayout(lineHeight: lineHeight)
        if balances {
            layout.balances = true
            layout.text = String(string.characters)
            layout.font = fonts.nsFont(role, size: size, weight: nsWeight)
            layout.kern = tracking
        }
        var recorder: SelectionRecorder?
        if let row, let selection { recorder = SelectionRecorder(store: selection.store, row: row, map: rich.map) }
        return layout {
            if rich.needsRenderer || recorder != nil {
                line.textRenderer(
                    PageTextRenderer(
                        tint: NativeTheme.tint,
                        link: NativeTheme.link,
                        radius: size * codeScale * 0.3,
                        size: size,
                        recorder: recorder
                    )
                )
                .background { if let row, let selection { SelectionLayer(row: row, selection: selection) } }
                .onGeometryChange(for: CGPoint.self) {
                    $0.frame(in: .named(NativeDocumentColumn.space)).origin
                } action: { origin in
                    if let row, let selection { selection.origins[row] = origin }
                }
            } else {
                line
            }
        }
        .offset(
            y: NativeMetrics.halfLeading(font: fonts.nsFont(role, size: size, weight: nsWeight), lineHeight: lineHeight)
        )
    }

    private var nsWeight: NSFont.Weight {
        switch weight {
            case .semibold: .semibold
            case .medium: .medium
            default: .regular
        }
    }
}
