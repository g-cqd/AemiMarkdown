/// Curly quotes, apostrophes and ellipses in the prose of a viewer (not in code, not in the terminal): the quote opens after white space, an opening bracket, a dash or the start of
/// a paragraph, and closes anywhere else. It needs the character that came before, which a paragraph's runs hand on.
@available(macOS 26.0, *)
struct SmartPunctuation {
    /// The last character written in this paragraph, or nil at its start.
    var previous: Unicode.Scalar?

    mutating func apply(_ text: String) -> String {
        var result = ""
        var iterator = Array(text.unicodeScalars)[...]
        while let scalar = iterator.popFirst() {
            var out = scalar
            switch scalar {
                case "\"": out = opens ? "\u{201C}" : "\u{201D}"
                case "'": out = opens ? "\u{2018}" : "\u{2019}"
                case ".":
                    if iterator.starts(with: [".", "."]) {
                        iterator.removeFirst(2)
                        result += "\u{2026}"
                        previous = "\u{2026}"
                        continue
                    }
                default: break
            }
            result.unicodeScalars.append(out)
            previous = out
        }
        return result
    }

    /// Whether a quote here opens a quotation.
    var opens: Bool {
        guard let previous else { return true }
        return previous.properties.isWhitespace || "([{\u{2014}\u{2013}-".unicodeScalars.contains(previous)
    }
}
