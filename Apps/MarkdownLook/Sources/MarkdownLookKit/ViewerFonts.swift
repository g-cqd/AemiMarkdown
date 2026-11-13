internal import Foundation

/// A typeface a style of the page may use (ask roadmap 0199, ADR 0004): one of the system's four, or a family installed on the machine, named. A page that names a family that is not installed
/// falls back to the system's.
@available(macOS 26.0, *)
public enum FontFace: Sendable, Equatable {
    case system, serif, rounded, mono
    case family(String)

    /// The words a preference holds: the four names, else a family name cut to the characters a family name has (so nothing a preferences file says can reach a style sheet as anything but a name).
    public init(_ value: String) {
        switch value {
            case "system": self = .system
            case "serif": self = .serif
            case "rounded": self = .rounded
            case "mono": self = .mono
            default:
                let name = String(value.unicodeScalars.filter(Self.allowed.contains).prefix(64).map(Character.init))
                    .trimmingCharacters(in: .whitespaces)
                self = name.isEmpty ? .system : .family(name)
        }
    }

    private static let allowed: Set<Unicode.Scalar> = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.".unicodeScalars
    )

    public var raw: String {
        switch self {
            case .system: "system"
            case .serif: "serif"
            case .rounded: "rounded"
            case .mono: "mono"
            case .family(let name): name
        }
    }

    /// The `font-family` list of a style sheet.
    var css: String {
        switch self {
            case .system: "-apple-system, system-ui, 'SF Pro Text', sans-serif"
            case .serif: "ui-serif, 'New York', Georgia, serif"
            case .rounded: "ui-rounded, 'SF Pro Rounded', system-ui, sans-serif"
            case .mono: "ui-monospace, 'SF Mono', Menlo, monospace"
            case .family(let name): "'\(name)', -apple-system, system-ui, sans-serif"
        }
    }
}

/// The fonts of the four styles the page has: its text, its headings, its code and monospace, and its diagrams; and the OpenType features turned on in all of them.
@available(macOS 26.0, *)
public struct ViewerFonts: Sendable, Equatable {
    /// A style may follow the text (`nil`): the headings and the diagrams do by default.
    public var text = FontFace.system
    public var heading: FontFace?
    public var code = FontFace.mono
    public var diagram: FontFace?
    /// OpenType feature tags with their values, as a person writes them: `ss01, tnum, cv11=2`.
    public var features: [Feature] = []

    public struct Feature: Sendable, Equatable {
        public var tag: String
        public var value: Int
    }

    public init() {}

    public var headingFace: FontFace { heading ?? text }
    public var diagramFace: FontFace { diagram ?? text }

    /// The features in a list a person wrote: tags of four letters or digits, each with an optional `=value` (1 when there is none), at most twelve, anything else left out.
    public static func features(_ words: String) -> [Feature] {
        var found: [Feature] = []
        for word in words.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let parts = word.split(separator: "=", maxSplits: 1)
            guard let tag = parts.first, tag.utf8.count == 4, tag.utf8.allSatisfy({ $0.isASCIIAlphanumeric }),
                found.count < 12
            else { continue }
            let value = parts.count == 2 ? Int(parts[1]) : 1
            guard let value, (0 ... 20).contains(value) else { continue }
            found.append(Feature(tag: String(tag), value: value))
        }
        return found
    }

    /// The words that write the features back.
    public var featureWords: String {
        features.map { $0.value == 1 ? $0.tag : "\($0.tag)=\($0.value)" }.joined(separator: ", ")
    }

    /// Typefaces as a reader names them (ADR 0004): all system; all serif; serif headings over sans text; sans headings over serif text.
    public enum Preset: String, Sendable, CaseIterable {
        case system, serif, serifDisplay, serifText

        public var fonts: ViewerFonts {
            var fonts = ViewerFonts()
            switch self {
                case .system: break
                case .serif: fonts.text = .serif
                case .serifDisplay: fonts.heading = .serif
                case .serifText:
                    fonts.text = .serif
                    fonts.heading = .system
                    fonts.diagram = .system
            }
            return fonts
        }
    }

    /// The rules these fonts add to the style sheet.
    var css: String {
        var rules = "html { font-family: \(text.css); }\n"
        if let heading { rules += "h1, h2, h3, h4, h5, h6 { font-family: \(heading.css); }\n" }
        rules += "code, pre { font-family: \(code.css); }\n"
        rules += "svg.mermaid { font-family: \(diagramFace.css); }\n"
        if !features.isEmpty {
            let list = features.map { "\"\($0.tag)\" \($0.value)" }.joined(separator: ", ")
            rules += "html { font-feature-settings: \(list); }\n"
        }
        return rules
    }
}

@available(macOS 26.0, *)
extension UInt8 {
    fileprivate var isASCIIAlphanumeric: Bool {
        (0x30 ... 0x39).contains(self) || (0x41 ... 0x5A).contains(self) || (0x61 ... 0x7A).contains(self)
    }
}
