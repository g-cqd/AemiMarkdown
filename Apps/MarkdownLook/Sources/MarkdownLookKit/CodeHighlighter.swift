internal import AemiLexers

/// Syntax colour for fenced code (ADR 0004): the scanners of AemiLexers (hand-written, one pass over the bytes, 20 languages) give tokens as byte ranges, and each becomes a `span` whose
/// class is one of nine kinds, coloured by the style sheet in light and dark. Anything else about the code (a language the scanners do not know, a block too large) stays plain.
enum CodeHighlighter {
    /// The largest block coloured, in bytes: a scan is linear, but a page of a few megabytes of spans is not what a preview is for.
    static let byteLimit = 256 << 10

    /// What a fence's info word names: the language itself, a common alias, or a file extension. Nil for plain text and for what is not known.
    static func language(for word: String) -> Language? {
        let name = word.lowercased()
        let language = aliases[name] ?? Language(fileExtension: name)
        return language == .plain ? nil : language
    }

    private static let aliases: [String: Language] = [
        "javascript": .javascript, "typescript": .typescript, "python": .python, "python3": .python, "shell": .shell,
        "console": .shell, "shellscript": .shell,
        "objc": .objectiveC, "objective-c": .objectiveC, "objectivec": .objectiveC, "c++": .cpp, "golang": .go,
        "ruby": .ruby, "rust": .rust, "kotlin": .kotlin,
        "yml": .yaml, "node": .javascript
    ]

    /// The class of a token's role, or nil for the roles that stay in the text colour.
    private static func kind(of role: HighlightRole) -> String? {
        switch role {
            case .keyword, .keywordFunction, .keywordReturn, .keywordOperator, .declarationOther, .boolean,
                .constantBuiltin:
                "k"
            case .string, .stringSpecial, .regex: "s"
            case .stringEscape, .escape: "e"
            case .number, .numberFloat, .constant: "n"
            case .comment, .commentDocumentation: "c"
            case .type, .typeBuiltin, .typeParameter, .typeDeclaration, .constructor, .namespace: "t"
            case .attribute, .label: "a"
            case .tag: "g"
            case .property, .propertyBuiltin: "p"
            default: nil
        }
    }

    /// `code` as escaped HTML with its tokens in spans. Tokens are ascending and disjoint; one that is not (it would be a bug in a scanner) is left uncoloured, so the text is whole whatever happens.
    static func html(_ code: [UInt8], language: Language) -> String {
        var out = ""
        out.reserveCapacity(code.count * 2)
        var position = 0
        for token in SyntaxHighlighter.tokens(utf8: code, language: language) {
            let range = token.byteRange
            guard range.lowerBound >= position, range.upperBound <= code.count, !range.isEmpty,
                let kind = kind(of: token.role)
            else { continue }
            out += HTMLText.escaped(String(decoding: code[position ..< range.lowerBound], as: UTF8.self))
            out +=
                "<span class=\"\(kind)\">" + HTMLText.escaped(String(decoding: code[range], as: UTF8.self)) + "</span>"
            position = range.upperBound
        }
        return out + HTMLText.escaped(String(decoding: code[position...], as: UTF8.self))
    }
}
