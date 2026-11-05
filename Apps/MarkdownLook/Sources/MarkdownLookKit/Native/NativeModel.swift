public import AemiMermaidScene
public import AemiMermaidSyntax
internal import Foundation
public import SwiftUI

/// A Markdown document as the rows a SwiftUI view lists (ADR 0004, ask roadmap 0199): every container (a quote, an alert, a list item, a footnote) becomes a column of guides at the left of
/// the rows inside it, the way TerminalKit makes prefixes, so nesting is a count of columns of one width and not a tree of views, and a row is a leaf block with the space above it decided.
public struct NativeRow: Identifiable, Sendable {
    public let id: Int
    public var guides: [NativeGuide]
    /// The space above the row in em of the body text: what the web page's style sheet gives it, in the em of its own font (a heading's space is in em of the heading).
    public var gap: Double
    public var content: NativeContent
}

/// A column to the left of a row, one indent wide.
public enum NativeGuide: Sendable, Equatable {
    /// A quote's bar or an alert's. `continues`: an earlier row is in the same container, so the bar runs on through the space above this one.
    case bar(NativeAlert?, continues: Bool)
    /// The marker of a list item or footnote, on its first row.
    case marker(NativeMarker)
    /// Nothing, under the marker, on the rows after the first.
    case indent
}

public enum NativeMarker: Sendable, Equatable {
    /// A bullet, by the depth of bulleted lists around it.
    case bullet(depth: Int)
    case number(String)
    case task(done: Bool)
    case note(String)
}

public enum NativeAlert: Int, Sendable, Equatable {
    case note = 1
    case tip, important, warning, caution

    public var title: String { ["Note", "Tip", "Important", "Warning", "Caution"][rawValue - 1] }
}

public enum NativeContent: Sendable {
    case text(NativeText)
    case code(NativeCode)
    case table(NativeTable)
    case diagram(NativeDiagram)
    case rule
    /// The short rule above the notes of a document.
    case footnoteRule
}

public struct NativeText: Sendable {
    public enum Style: Sendable, Equatable {
        case body
        case heading(Int)
        case alertTitle
        case note
    }

    public var string: AttributedString
    public var style: Style
}

public struct NativeCode: Sendable {
    /// The language the fence names (empty for none), and the code as it was written, for copying.
    public var language: String
    public var raw: String
    /// The code as shown: tabs expanded, coloured when a scanner knows the language.
    public var shown: AttributedString
    public var isHTML: Bool
}

public struct NativeTable: Sendable {
    public enum Alignment: Sendable, Equatable { case leading, center, trailing }

    public var alignments: [Alignment]
    public var header: [AttributedString]
    public var rows: [[AttributedString]]
}

public enum NativeDiagram: Sendable {
    case scene(DiagramScene)
    case pie(PieDiagram)
}

/// A document read once into rows.
public struct NativeDocument: Sendable {
    public var rows: [NativeRow] = []
    /// The row of each footnote's definition, and of its first reference, by label.
    public var noteRow: [String: Int] = [:]
    public var referenceRow: [String: Int] = [:]

    public init() {}

    /// A document that is one diagram, as a Mermaid file is.
    public init(diagram source: String, settings: ViewerSettings = ViewerSettings()) {
        self = NativeBuilder.diagramDocument(source, settings: settings)
    }
}

/// The scheme of the links inside a document that move to a footnote and back (a footnote's label is percent-encoded after the colon).
public enum NativeLink {
    public static let note = "markdownlook-note"
    public static let reference = "markdownlook-ref"

    public static func url(_ scheme: String, label: String) -> URL? {
        URL(string: scheme + ":" + (label.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
    }

    /// The label of a note link or a back link, and which it is.
    public static func parse(_ url: URL) -> (scheme: String, label: String)? {
        guard url.scheme == note || url.scheme == reference,
            let label = url.absoluteString.split(separator: ":", maxSplits: 1).last
        else { return nil }
        return (url.scheme ?? "", String(label).removingPercentEncoding ?? "")
    }
}
