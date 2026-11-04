internal import Foundation

/// What a reader may choose about the page (ADR 0004): whether text uses the whole width of the window and how wide a tab is in code. The app writes them into its preferences domain
/// and the preview extension reads that domain, so one choice shows in the app and in Quick Look.
public struct ViewerSettings: Sendable, Equatable {
    /// A preferences domain of its own, outside the sandbox containers: the app (read and write) and the preview extension (read only) each hold a sandbox exception for it, which is how
    /// a choice made in the app reaches Quick Look without an app group (that needs a provisioning profile).
    public static let domain = "studio.aemi.MarkdownLook.shared"
    public static let fullWidthKey = "fullWidth"
    public static let tabSizeKey = "tabSize"
    public static let tabSizes = 1 ... 8
    public static let defaultTabSize = 4

    /// Text runs the whole width of the window instead of a column of about 40 em.
    public var fullWidth: Bool
    /// The width of a tab character in code, in spaces.
    public var tabSize: Int

    public init(fullWidth: Bool = false, tabSize: Int = defaultTabSize) {
        self.fullWidth = fullWidth
        self.tabSize = Swift.min(Self.tabSizes.upperBound, Swift.max(Self.tabSizes.lowerBound, tabSize))
    }

    /// The settings in the app's preferences domain; defaults for what is not set or not valid.
    public static func current() -> ViewerSettings {
        let full = CFPreferencesCopyAppValue(fullWidthKey as CFString, domain as CFString) as? Bool
        let tab = CFPreferencesCopyAppValue(tabSizeKey as CFString, domain as CFString) as? Int
        return ViewerSettings(fullWidth: full ?? false, tabSize: tab ?? defaultTabSize)
    }

    /// The rules these settings add to the style sheet. Numbers and booleans only: nothing a document or a preferences file says is written into it.
    var css: String {
        var rules = "pre, code { tab-size: \(tabSize); -moz-tab-size: \(tabSize); }\n"
        if fullWidth { rules += "main { max-width: none; } .table-wrap.wide { margin-inline: 0; }\n" }
        return rules
    }
}
