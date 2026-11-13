internal import AppKit
internal import SwiftUI

/// Colours that follow the appearance, for what the system's own do not cover: the tones of syntax colour.
@available(macOS 26.0, *)
enum NativeTheme {
    /// The page's own colours (`:root` in the style sheet), light and dark, as hex with an alpha.
    private static func page(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let hex = isDark ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: isDark ? darkAlpha : lightAlpha
                )
            }
        )
    }

    static let text = page(light: 0x1d1d1f, dark: 0xececf0)
    static let secondary = page(light: 0x6e6e73, dark: 0x98989d)
    static let tertiary = page(light: 0xa1a1a6, dark: 0x636366)
    static let pieMuted = page(light: 0x8e8e93, dark: 0x8e8e93)
    static let diagramFill = page(light: 0xfafafa, dark: 0x2a2a2c)
    static let surface = Color(nsColor: .textBackgroundColor)
    static let note = page(light: 0x8e8e93, dark: 0x8e8e93)
    static let link = page(light: 0x0a64d6, dark: 0x4da3ff)
    static let rule = page(light: 0, dark: 0xffffff, lightAlpha: 0.10, darkAlpha: 0.13)
    static let tint = page(light: 0, dark: 0xffffff, lightAlpha: 0.045, darkAlpha: 0.07)
    static let mark = page(light: 0, dark: 0xffffff, lightAlpha: 0.28, darkAlpha: 0.35)

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let (r, g, b) = isDark ? dark : light
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            }
        )
    }

    /// The muted tones of a pie's slices, in order.
    static func pie(_ index: Int) -> Color {
        let tones: [((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))] = [
            ((0.42, 0.50, 0.60), (0.51, 0.60, 0.71)), ((0.56, 0.68, 0.62), (0.62, 0.75, 0.68)),
            ((0.80, 0.73, 0.56), (0.85, 0.78, 0.61)), ((0.75, 0.56, 0.53), (0.81, 0.62, 0.59)),
            ((0.64, 0.58, 0.74), (0.70, 0.65, 0.80)), ((0.53, 0.68, 0.75), (0.60, 0.75, 0.82)),
            ((0.85, 0.80, 0.65), (0.88, 0.83, 0.69)), ((0.66, 0.62, 0.58), (0.73, 0.69, 0.64))
        ]
        let tone = tones[index % tones.count]
        return dynamic(light: tone.0, dark: tone.1)
    }

    /// The colour of a token of the kind letter `CodeHighlighter` gives (keyword, string, escape, number, type, attribute, tag, property, comment).
    static func token(_ kind: String) -> Color {
        switch kind {
            case "k", "g": dynamic(light: (0.61, 0.14, 0.58), dark: (1, 0.48, 0.70))
            case "s": dynamic(light: (0.76, 0.22, 0.12), dark: (1, 0.56, 0.48))
            case "e": dynamic(light: (0.69, 0.32, 0.12), dark: (1, 0.69, 0.52))
            case "n": dynamic(light: (0.11, 0.37, 0.82), dark: (0.85, 0.79, 0.49))
            case "t": dynamic(light: (0.12, 0.44, 0.48), dark: (0.42, 0.83, 0.91))
            case "a": dynamic(light: (0.54, 0.35, 0.08), dark: (0.88, 0.70, 0.42))
            case "p": dynamic(light: (0.23, 0.43, 0.65), dark: (0.54, 0.71, 0.94))
            default: dynamic(light: (0.48, 0.50, 0.54), dark: (0.49, 0.52, 0.56))
        }
    }
}
