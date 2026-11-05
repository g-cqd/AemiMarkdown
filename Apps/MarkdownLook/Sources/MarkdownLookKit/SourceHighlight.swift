internal import AemiMarkdown
internal import AemiTextStyling
public import AppKit

/// Colour for Markdown *source* in an editor (the lab's left pane): attributes only, so every character stays as typed and editing, the cursor, selection and undo are untouched. What the bytes are comes from
/// `MarkdownSourceHighlighter` (the colouring ask's prompt has, made neutral); how they look is decided here, with the system's semantic colours so light, dark and the accent follow the system.
///
/// The font does not change size anywhere: a heading is bold and tinted, not larger, so lines keep one height and the editor's scroll position and the lab's measurements stay put.
@MainActor
public enum MarkdownSourceHighlight {
    /// Styles the Markdown in `storage`: all of it, or the UTF-8 byte `window` of it (a long text is parsed only around the window).
    /// - Complexity: O(the text copied) plus the parse of the window, or of the first megabyte when there is none.
    public static func apply(to storage: NSTextStorage, font: NSFont, window: Range<Int>? = nil) {
        let bytes = Array(storage.string.utf8)
        let spans = MarkdownSourceHighlighter.spans(of: bytes, visible: window)
        var cache: [MarkdownSourceStyle: [NSAttributedString.Key: Any]] = [:]
        TextStorageStyler.apply(
            spans.map { (bytes: $0.bytes, style: $0.style) },
            to: storage,
            window: window,
            base: baseAttributes(font: font)
        ) { style in
            if let known = cache[style] { return known }
            let made = attributes(for: style, font: font)
            cache[style] = made
            return made
        }
    }

    /// As ``apply(to:font:window:)``, for a window given in the UTF-16 units of the storage (what a text view reports): a text of 8 KiB or less is styled whole, a longer one only around `visible`.
    public static func apply(to storage: NSTextStorage, font: NSFont, visible: NSRange) {
        let string = storage.string
        let low = TextStorageStyler.byteOffset(ofUTF16: visible.location, in: string)
        let high = TextStorageStyler.byteOffset(ofUTF16: NSMaxRange(visible), in: string)
        apply(to: storage, font: font, window: low ..< high)
    }

    static func baseAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }

    /// What a style looks like, on top of the base attributes.
    static func attributes(for style: MarkdownSourceStyle, font: NSFont) -> [NSAttributedString.Key: Any] {
        var result = baseAttributes(font: font)
        switch style.kind {
            case .marker:
                result[.foregroundColor] = NSColor.tertiaryLabelColor
            case .code:
                result[.foregroundColor] = NSColor.systemOrange
                result[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
            case .codeLabel:
                result[.foregroundColor] = NSColor.systemTeal
            case .linkTarget:
                result[.foregroundColor] = NSColor.systemBlue.withAlphaComponent(0.7)
            case .html:
                result[.foregroundColor] = NSColor.systemPurple
            case .text:
                break
        }
        if style.kind == .text {
            var styled = font
            if style.traits.contains(.strong) || style.headingLevel > 0 { styled = bold(styled) }
            if style.traits.contains(.emphasis) {
                let slanted = italic(styled)
                // A monospaced face has no italic: slant it instead, so emphasis shows.
                if slanted == styled { result[.obliqueness] = 0.18 }
                styled = slanted
            }
            result[.font] = styled
            if style.traits.contains(.strikethrough) { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if style.traits.contains(.link) { result[.foregroundColor] = NSColor.linkColor }
            if style.headingLevel > 0 { result[.foregroundColor] = NSColor.controlAccentColor }
        }
        return result
    }

    private static func bold(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
}
