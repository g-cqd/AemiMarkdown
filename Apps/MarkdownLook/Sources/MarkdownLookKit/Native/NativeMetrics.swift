internal import AppKit

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
