internal import AppKit
internal import Foundation
internal import SwiftUI

/// Marks the text of a code span, so that the renderer below draws a tint behind it.
struct CodePill: TextAttribute {}

/// Marks the text of a link, so that the renderer below draws its underline.
struct LinkUnderline: TextAttribute {}

/// Draws a text as SwiftUI would, with what a page adds to it: the rounded tint behind inline code (the rectangle of the run, a font's ascent and descent as an inline box has them, rounded by
/// 0.3 em), and under a link a line one point thick, 0.22 em below the baseline, in the link's colour at 35 %.
struct PageTextRenderer: TextRenderer {
    let tint: Color
    let link: Color
    let radius: CGFloat
    let size: CGFloat

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
    static func text(_ string: AttributedString, size: CGFloat) -> (text: Text, needsRenderer: Bool) {
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
                    piece = piece.font(.system(size: size * 0.75)).baselineOffset(size * 0.35)
                } else {
                    piece = piece.customAttribute(LinkUnderline())
                    needsRenderer = true
                }
            }
            if intent.contains(.code) {
                let pad = size * 0.9 * 0.3
                let edge = Text("\u{00A0}").font(.system(size: pad / spaceWidth, design: .monospaced))
                piece = piece.font(.system(size: size * 0.9, design: .monospaced))
                piece = Text("\(edge)\(piece)\(edge)").customAttribute(CodePill())
                needsRenderer = true
            }
            interpolation.appendInterpolation(piece)
        }
        return (Text(LocalizedStringKey(stringInterpolation: interpolation)), needsRenderer)
    }

    /// The width of a space of the monospaced font, in ems: the room a code span's side padding is made of (a space of a smaller font than the code's, so that the line's height does not change).
    private static func monospacedSpace() -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
        return NSAttributedString(string: "\u{00A0}", attributes: [.font: font]).size().width / 100
    }
}
