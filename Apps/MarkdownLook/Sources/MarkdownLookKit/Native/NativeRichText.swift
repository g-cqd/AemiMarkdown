internal import AppKit
internal import Foundation
internal import SwiftUI

/// Marks the text of a code span, so that the renderer below draws a tint behind it.
struct CodePill: TextAttribute {}

/// Marks the number of a footnote reference, drawn raised: a raised run in the text itself would push its line's glyphs down, where a page's `line-height: 0` leaves the line alone.
struct NoteRaise: TextAttribute {}

/// Marks the text of a link, so that the renderer below draws its underline.
struct LinkUnderline: TextAttribute {}

/// Draws a text as SwiftUI would, with what a page adds to it: the rounded tint behind inline code (the rectangle of the run, a font's ascent and descent as an inline box has them, rounded by
/// 0.3 em), and under a link a line one point thick, 0.22 em below the baseline, in the link's colour at 35 %.
struct PageTextRenderer: TextRenderer {
    let tint: Color
    let link: Color
    let radius: CGFloat
    let size: CGFloat
    var raise: CGFloat { size * 0.40 }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
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
enum NativeRichText {
    /// The text, and whether it needs the page's renderer.
    static func text(_ string: AttributedString, size: CGFloat, code codeScale: CGFloat = 0.9) -> (
        text: Text, needsRenderer: Bool
    ) {
        var needsRenderer = false
        var interpolation = LocalizedStringKey.StringInterpolation(
            literalCapacity: 0,
            interpolationCount: string.runs.count
        )
        let spaceWidth = monospacedSpace()
        for run in string.runs {
            var plain = AttributedString(string[run.range])
            plain.inlinePresentationIntent = nil
            plain.strikethroughStyle = nil
            plain.foregroundColor = nil
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { plain = Self.breakableAfterHyphens(plain) }
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
                    let edge = Text("\u{00A0}").font(.system(size: size * 0.75 * 0.1 / spaceWidth, design: .monospaced))
                    piece = Text("\(edge)\(piece.font(.system(size: size * 0.75)))\(edge)").customAttribute(NoteRaise())
                    needsRenderer = true
                } else {
                    piece = piece.customAttribute(LinkUnderline())
                    needsRenderer = true
                }
            }
            if intent.contains(.code) {
                let pad = size * codeScale * 0.3
                let edge = Text("\u{00A0}").font(.system(size: pad / spaceWidth, design: .monospaced))
                piece = piece.font(.system(size: size * codeScale, design: .monospaced))
                piece = Text("\(edge)\(piece)\(edge)").customAttribute(CodePill())
                needsRenderer = true
            }
            interpolation.appendInterpolation(piece)
        }
        return (Text(LocalizedStringKey(stringInterpolation: interpolation)), needsRenderer)
    }

    /// A code span breaks as the page breaks it: after a hyphen, which the typesetter takes as no place to break (it falls back to a slash), and not after a slash, which it takes as one.
    private static func breakableAfterHyphens(_ text: AttributedString) -> AttributedString {
        var out = text
        let characters = Array(text.characters)
        var offset = 0
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
            offset += 1
        }
        return out
    }

    /// The width of a space of the monospaced font, in ems: the room a code span's side padding is made of (a space of a smaller font than the code's, so that the line's height does not change).
    private static func monospacedSpace() -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
        return NSAttributedString(string: "\u{00A0}", attributes: [.font: font]).size().width / 100
    }
}

/// A run of text as the style sheet sets it: the font at its size and weight, a line of an exact height (the half leading above the glyphs, as a page has it), a whole number of lines, a heading's
/// balance and letter spacing, and the code, links and notes of `NativeRichText`.
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

    var body: some View {
        let rich = NativeRichText.text(string, size: size, code: codeScale)
        var font = Font.system(size: size, weight: weight)
        if digits { font = font.monospacedDigit() }
        let line = rich.text.font(font).foregroundColor(color).lineHeight(.exact(points: lineHeight))
            .textCase(uppercase ? .uppercase : nil).tracking(tracking).fixedSize(horizontal: !wraps, vertical: true)
        var layout = BalancedLayout(lineHeight: lineHeight)
        if balances {
            layout.balances = true
            layout.text = String(string.characters)
            layout.font = NSFont.systemFont(ofSize: size, weight: weight == .semibold ? .semibold : .regular)
            layout.kern = tracking
        }
        return layout {
            if rich.needsRenderer {
                line.textRenderer(
                    PageTextRenderer(
                        tint: NativeTheme.tint,
                        link: NativeTheme.link,
                        radius: size * codeScale * 0.3,
                        size: size
                    )
                )
            } else {
                line
            }
        }
        .offset(y: NativeMetrics.halfLeading(size: size, weight: nsWeight, lineHeight: lineHeight))
    }

    private var nsWeight: NSFont.Weight {
        switch weight {
            case .semibold: .semibold
            case .medium: .medium
            default: .regular
        }
    }
}
