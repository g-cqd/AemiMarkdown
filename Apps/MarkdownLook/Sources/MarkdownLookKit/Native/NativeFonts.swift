internal import AppKit
internal import CoreText
internal import SwiftUI

/// The four styles of the page that have a font of their own.
enum FontRole: Sendable {
    case text, heading, code, diagram
}

/// The fonts the native view sets its styles in, from the viewer's settings: the same choices the style sheet makes, resolved to SwiftUI fonts for drawing and to AppKit fonts for measuring (line
/// metrics, balance, column widths). With nothing but the system's faces and no features the SwiftUI font is the system's own, so what was measured against the page stays as it was.
struct NativeFonts: Sendable, Equatable {
    var settings = ViewerFonts()

    init(_ fonts: ViewerFonts = ViewerFonts()) { settings = fonts }

    func face(_ role: FontRole) -> FontFace {
        switch role {
            case .text: settings.text
            case .heading: settings.headingFace
            case .code: settings.code
            case .diagram: settings.diagramFace
        }
    }

    /// The font for drawing.
    func font(_ role: FontRole, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if settings.features.isEmpty {
            switch face(role) {
                case .system: return .system(size: size, weight: weight)
                case .serif: return .system(size: size, weight: weight, design: .serif)
                case .rounded: return .system(size: size, weight: weight, design: .rounded)
                case .mono: return .system(size: size, weight: weight, design: .monospaced)
                case .family: break
            }
        }
        return Font(nsFont(role, size: size, weight: Self.nsWeight(weight)))
    }

    /// The font for measuring: the one `font` draws.
    func nsFont(_ role: FontRole, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var font: NSFont
        switch face(role) {
            case .system: font = base
            case .serif: font = Self.design(.serif, of: base)
            case .rounded: font = Self.design(.rounded, of: base)
            case .mono: font = .monospacedSystemFont(ofSize: size, weight: weight)
            case .family(let name):
                let descriptor = NSFontDescriptor(fontAttributes: [.family: name])
                    .addingAttributes([
                        .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
                    ])
                font = NSFont(descriptor: descriptor, size: size) ?? base
                if font.familyName?.caseInsensitiveCompare(name) != .orderedSame { font = base }
        }
        guard !settings.features.isEmpty else { return font }
        let features = settings.features.map {
            [
                NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String): $0.tag,
                NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String): $0.value
            ]
        }
        font =
            NSFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: features]), size: size) ?? font
        return font
    }

    private static func design(_ design: NSFontDescriptor.SystemDesign, of font: NSFont) -> NSFont {
        font.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
    }

    static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
            case .ultraLight: .ultraLight
            case .thin: .thin
            case .light: .light
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            case .black: .black
            default: .regular
        }
    }
}

extension EnvironmentValues {
    @Entry var pageFonts = NativeFonts()
}
