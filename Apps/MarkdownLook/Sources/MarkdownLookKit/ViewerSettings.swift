internal import Foundation

/// What a backdrop the page and the window sit on: opaque, the system's blurred material, or nothing at all (ADR 0004).
public enum Backdrop: String, Sendable, CaseIterable {
    /// The page has the window's own opaque background: the most contrast, for text over anything.
    case solid
    /// The page is transparent and the app puts the system's blurred material behind it. Quick Look draws its own backdrop behind a transparent page.
    case blurred
    /// The page is transparent and the window is clear: what is behind the window shows through.
    case clear
}

/// What a reader may choose (ADR 0004): every behaviour the viewer assumes is one of these, with the default it ships with. The app writes them into a preferences domain of its own and the
/// preview extension reads that domain, so one choice shows in the app and in Quick Look.
public struct ViewerSettings: Sendable, Equatable {
    /// A preferences domain outside the sandbox containers: the app (read and write) and the preview extension (read only) each hold a sandbox exception for it, which is how a choice made in the
    /// app reaches Quick Look without an app group (that needs a provisioning profile).
    public static let domain = "studio.aemi.MarkdownLook.shared"

    /// The keys of the domain, and the ranges and defaults of the numbers.
    public enum Key {
        public static let fullWidth = "fullWidth"
        public static let tabSize = "tabSize"
        public static let textSize = "textSize"
        public static let smartPunctuation = "smartPunctuation"
        public static let highlightsCode = "highlightsCode"
        public static let showsLanguage = "showsLanguage"
        public static let drawsDiagrams = "drawsDiagrams"
        public static let rowLines = "rowLines"
        public static let columnLines = "columnLines"
        public static let outerBorder = "outerBorder"
        public static let scrollsTables = "scrollsTables"
        public static let backdrop = "backdrop"
    }
    public static let tabSizes = 1 ... 8
    public static let defaultTabSize = 4
    public static let textSizes = 11 ... 20
    public static let defaultTextSize = 13

    /// Text runs the whole width of the window instead of a column of about 40 em.
    public var fullWidth = false
    /// The width of a tab character in code, in spaces.
    public var tabSize = defaultTabSize { didSet { tabSize = Self.clamp(tabSize, Self.tabSizes) } }
    /// The size of the body text in points; everything else is in em of it.
    public var textSize = defaultTextSize { didSet { textSize = Self.clamp(textSize, Self.textSizes) } }
    /// Curly quotes and ellipses in prose (never in code).
    public var smartPunctuation = true
    /// Colour in fenced code, for the languages the scanners know.
    public var highlightsCode = true
    /// The language a fence names, in the corner of its block.
    public var showsLanguage = true
    /// Mermaid fences as diagrams; off shows them as code.
    public var drawsDiagrams = true
    /// A hairline between the rows of a table.
    public var rowLines = true
    /// A hairline between the columns of a table.
    public var columnLines = false
    /// A rounded outline around a table.
    public var outerBorder = false
    /// A table keeps each cell on one line and scrolls sideways when it is wider than the window; off, long cells wrap down to their longest word before it scrolls.
    public var scrollsTables = false
    public var backdrop = Backdrop.blurred

    public init() {}

    public init(fullWidth: Bool = false, tabSize: Int = defaultTabSize) {
        self.fullWidth = fullWidth
        self.tabSize = Self.clamp(tabSize, Self.tabSizes)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, value))
    }

    /// The settings in the preferences domain; the default for what is not set or not of the right kind.
    public static func current(domain: String = ViewerSettings.domain) -> ViewerSettings {
        func value(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain as CFString) }
        var settings = ViewerSettings()
        settings.fullWidth = value(Key.fullWidth) as? Bool ?? settings.fullWidth
        settings.tabSize = clamp(value(Key.tabSize) as? Int ?? defaultTabSize, tabSizes)
        settings.textSize = clamp(value(Key.textSize) as? Int ?? defaultTextSize, textSizes)
        settings.smartPunctuation = value(Key.smartPunctuation) as? Bool ?? settings.smartPunctuation
        settings.highlightsCode = value(Key.highlightsCode) as? Bool ?? settings.highlightsCode
        settings.showsLanguage = value(Key.showsLanguage) as? Bool ?? settings.showsLanguage
        settings.drawsDiagrams = value(Key.drawsDiagrams) as? Bool ?? settings.drawsDiagrams
        settings.rowLines = value(Key.rowLines) as? Bool ?? settings.rowLines
        settings.columnLines = value(Key.columnLines) as? Bool ?? settings.columnLines
        settings.outerBorder = value(Key.outerBorder) as? Bool ?? settings.outerBorder
        settings.scrollsTables = value(Key.scrollsTables) as? Bool ?? settings.scrollsTables
        settings.backdrop = (value(Key.backdrop) as? String).flatMap(Backdrop.init(rawValue:)) ?? settings.backdrop
        return settings
    }

    /// The rules these settings add to the style sheet. Numbers, booleans and fixed words only: nothing a document or a preferences file says is written into it.
    var css: String {
        var rules = "html { font-size: \(textSize)px; }\npre, code { tab-size: \(tabSize); }\n"
        if fullWidth { rules += "main { max-width: none; } .table-wrap.wide { margin-inline: 0; }\n" }
        if backdrop == .solid { rules += "html, body { background: Canvas; }\n" }
        if scrollsTables { rules += "th, td { white-space: nowrap; } td[style] { min-width: 0 !important; }\n" }
        if !rowLines { rules += "th::after, td::after { display: none; }\n" }
        if columnLines {
            rules +=
                "th + th::before, td + td::before { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: var(--hair); border-radius: 1px; background: var(--rule); }\n"
        }
        if outerBorder {
            rules +=
                ".table-wrap { border: var(--hair) solid var(--rule); border-radius: var(--radius); width: fit-content; max-width: 100%; }\n"
            rules += ".table-wrap.wide { max-width: min(68em, 100vw - 5em); margin-inline: auto; }\n"
            rules +=
                "th:first-child, td:first-child { padding-left: 1.4em; } th:last-child, td:last-child { padding-right: 1.4em; }\n"
            rules += "tbody tr:last-child td::after { display: none; }\n"
        }
        return rules
    }
}
