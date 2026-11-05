internal import AppKit
internal import SwiftUI

/// Where a page puts the glyphs of a line and where SwiftUI does.
enum NativeMetrics {
    /// A page (CSS `line-height`) puts half of the leading above the glyphs and half below. SwiftUI's exact line height puts all of it below, so a line is drawn this far lower to sit where the page
    /// has it. Measured against WebKit at 11 to 20 points (the page rounds the font's metrics and the screen rounds both), half a point less than the half itself; never up.
    static func halfLeading(size: CGFloat, weight: NSFont.Weight, lineHeight: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let natural = font.ascender - font.descender + font.leading
        return Swift.max(0, (lineHeight - natural) / 2 - 0.5)
    }
}

extension NativeMetrics {
    /// How far to move a block of lines set exactly to the height `lineHeight` so that its baselines sit where a page puts them: a page centres the font's own height in the line, and the line's
    /// baseline is that of the `strut` (the size of the element the line is in), which is the font's own size unless the text is smaller than its block. Half a point less, as measured.
    static func shift(size: CGFloat, design: Font.Design, strut: CGFloat, lineHeight: CGFloat) -> CGFloat {
        func font(_ points: CGFloat) -> NSFont {
            design == .monospaced
                ? .monospacedSystemFont(ofSize: points, weight: .regular) : .systemFont(ofSize: points)
        }
        let own = font(size)
        let block = font(strut)
        let natural = block.ascender - block.descender + block.leading
        let baseline = (lineHeight - natural) / 2 + block.ascender
        return Swift.max(0, baseline - own.ascender - 0.5)
    }
}
