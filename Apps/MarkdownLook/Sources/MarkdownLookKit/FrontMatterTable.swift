internal import AemiFrontMatter
internal import AemiHMMML
internal import AemiJSONCore
public import AemiMarkdown

extension MarkdownLook {
    /// What MarkdownLook reads: GitHub's Markdown, and a document's head (`---` YAML, `+++` TOML, a leading JSON object), which GitHub
    /// draws as a table.
    public static let extensions: MarkdownExtensions = [.github, .frontMatter]
}

/// MarkdownLook's own names.
public enum MarkdownLook {}

/// A document's head as GitHub draws it: its keys as a header row and its values as one row. A scalar shows its text, a list of
/// scalars its items joined by commas, anything deeper its compact JSON. Nil when the document has no head, or its head is not a
/// mapping, or does not read without a diagnostic: such a head is shown as its lines, as code in its format.
struct FrontMatterTable: Equatable {
    var keys: [String]
    var values: [String]

    init?(_ document: MarkdownDocument) {
        guard let reading = document.readFrontMatter(), reading.diagnostics.recorded.isEmpty, let value = reading.value
        else {
            return nil
        }
        let json: JSONValue =
            switch value {
                case .yaml(let head): head.json
                case .toml(let head): head.json
                case .json(let head): head
            }
        // Through `Sequence`, in the head's order, without importing the ordered dictionary's own module.
        guard case .object(let object) = json else { return nil }
        let members = object.map { ($0.key, $0.value) }
        guard !members.isEmpty else { return nil }
        keys = members.map(\.0)
        values = members.map { Self.cell($0.1) }
    }

    /// The head as written, fences included: what copying it gives.
    static func source(of document: MarkdownDocument) -> String? {
        guard let head = document.frontMatter, head.range.upperBound <= document.source.count else { return nil }
        return String(decoding: document.source[head.range], as: UTF8.self)
    }

    /// The language a head is shown in when it is shown as code.
    static func language(of document: MarkdownDocument) -> String {
        switch document.frontMatter?.format {
            case .toml?: "toml"
            case .json?: "json"
            default: "yaml"
        }
    }

    private static func cell(_ value: JSONValue) -> String {
        switch value {
            case .null: ""
            case .string(let text): text
            case .array(let items) where items.allSatisfy(\.isScalar): items.map(cell).joined(separator: ", ")
            default: (try? value.encodedBytes()).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
    }
}

extension JSONValue {
    fileprivate var isScalar: Bool {
        switch self {
            case .array, .object: false
            default: true
        }
    }
}
