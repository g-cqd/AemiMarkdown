internal import AppKit
internal import SwiftUI

/// Colours that follow the appearance, for what the system's own do not cover: the tones of syntax colour.
enum NativeTheme {
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
