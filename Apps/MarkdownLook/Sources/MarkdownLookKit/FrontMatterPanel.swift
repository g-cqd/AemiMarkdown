internal import AemiFrontMatter
internal import AemiHMMML
internal import AemiJSONCore
internal import AemiKernel
public import AemiMarkdown
internal import Foundation

extension MarkdownLook {
    /// What MarkdownLook reads: GitHub's Markdown, and a document's head (`---` YAML, `+++` TOML, a leading JSON object).
    public static let extensions: MarkdownExtensions = [.github, .frontMatter]
}

/// MarkdownLook's own names.
public enum MarkdownLook {}

/// A document's head as a panel of its properties, one row a key: a nested mapping's keys indented under it, a list of scalars as
/// tags, a flag as a check, a date as a reader would write it, an absolute web or mail address as a link. Both views draw it, closed
/// to one line (its format, its title, how many properties) until opened. Nil when the document has no head, or its head is not a
/// mapping, or does not read without a diagnostic: such a head is shown as its lines, as code in its format.
public struct FrontMatterPanel: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case text(String)
        case link(String)
        case date(String)
        case flag(Bool)
        case tags([String])
        /// A null, or a key whose rows follow it, indented.
        case none
    }

    public struct Row: Sendable, Equatable {
        public var key: String
        public var value: Value
        /// 0 for the head's own keys, one more for each mapping or list a row is inside.
        public var depth: Int
    }

    /// `YAML`, `TOML` or `JSON`.
    public var format: String
    /// The `title` (or `name`) property's text, for the closed panel.
    public var title: String?
    /// The head's own keys.
    public var count: Int
    public var rows: [Row]

    init?(_ document: MarkdownDocument, locale: Locale = .current, timeZone: TimeZone = .current) {
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
        format = Self.language(of: document).uppercased()
        count = members.count
        title = members.first { $0.0 == "title" || $0.0 == "name" }
            .flatMap { if case .string(let text) = $0.1 { text } else { nil } }
        rows = Self.rows(members, dates: DateText(locale: locale, timeZone: timeZone))
    }

    /// The rows of `members` and of everything inside them, in order, with an explicit stack.
    private static func rows(_ members: [(String, JSONValue)], dates: DateText) -> [Row] {
        var rows: [Row] = []
        var pending = members.reversed().map { (key: $0.0, value: $0.1, depth: 0) }
        while let (key, value, depth) = pending.popLast() {
            switch value {
                case .object(let object):
                    rows.append(Row(key: key, value: .none, depth: depth))
                    pending += object.map { ($0.key, $0.value) }.reversed()
                        .map { (key: $0.0, value: $0.1, depth: depth + 1) }
                case .array(let items) where items.allSatisfy(\.isScalar):
                    rows.append(Row(key: key, value: .tags(items.map(scalarText)), depth: depth))
                case .array(let items):
                    rows.append(Row(key: key, value: .none, depth: depth))
                    pending += items.enumerated().reversed()
                        .map { (key: String($0.offset + 1), value: $0.element, depth: depth + 1) }
                default: rows.append(Row(key: key, value: scalar(value, dates: dates), depth: depth))
            }
        }
        return rows
    }

    private static func scalar(_ value: JSONValue, dates: DateText) -> Value {
        switch value {
            case .null: .none
            case .bool(let flag): .flag(flag)
            case .string(let text):
                if let date = dates.readable(text) {
                    .date(date)
                } else if isWebOrMail(text) {
                    .link(text)
                } else {
                    // A block scalar ends with its newline (`>` and `|` keep one): the line it would add is not part of the value.
                    .text(String(text.reversed().drop { $0 == "\n" }.reversed()))
                }
            default: .text(scalarText(value))
        }
    }

    private static func scalarText(_ value: JSONValue) -> String {
        switch value {
            case .string(let text): text
            case .null: ""
            default: (try? value.encodedBytes()).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
    }

    /// An absolute `http`, `https` or `mailto` address: a relative one has nothing to be relative to in a preview.
    private static func isWebOrMail(_ text: String) -> Bool {
        let lower = text.lowercased()
        return (lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:"))
            && !text.contains(where: \.isWhitespace) && HTMLText.isSafeDestination(text)
    }

    /// The language a head is shown in when it is shown as code.
    static func language(of document: MarkdownDocument) -> String {
        switch document.frontMatter?.format {
            case .toml?: "toml"
            case .json?: "json"
            default: "yaml"
        }
    }

    /// The head as written, fences included: what copying it gives.
    static func source(of document: MarkdownDocument) -> String? {
        guard let head = document.frontMatter, head.range.upperBound <= document.source.count else { return nil }
        return String(decoding: document.source[head.range], as: UTF8.self)
    }
}

/// RFC 3339 dates and date-times (TOML's forms; a space for the `T`), as the reader's locale writes them: an instant in their time
/// zone, a local date or date-time as written. Jekyll's form (`2026-03-14 09:30:00 +0100`, Ruby's) and YAML 1.1's
/// (`2001-12-14 21:59:43.10 -5`), with white space before an offset that may lack its colon or its minutes, read as the instants
/// they are. Anything else is not a date here.
struct DateText {
    let locale: Locale
    let timeZone: TimeZone

    func readable(_ text: String) -> String? {
        guard text.count >= 10,
            let moment = RFC3339DateTime(
                parsing: Self.spacedOffset(Array(text.utf8))[...],
                syntax: [.toml11, .spaceSeparator]
            )
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        switch moment.kind {
            case .offsetDateTime:
                guard let date = Date(dateTime: moment) else { return nil }
                formatter.timeZone = timeZone
                formatter.timeStyle = .short
                return formatter.string(from: date)
            case .localDate, .localDateTime:
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC") ?? timeZone
                let components = DateComponents(
                    year: moment.year,
                    month: moment.month,
                    day: moment.day,
                    hour: moment.hour,
                    minute: moment.minute
                )
                guard let date = calendar.date(from: components) else { return nil }
                formatter.timeZone = calendar.timeZone
                formatter.timeStyle = moment.kind == .localDate ? .none : .short
                return formatter.string(from: date)
            case .localTime: return nil
        }
    }
}

extension DateText {
    /// `YYYY-MM-DD hh:mm:ss[.f] ±h[h][[:]mm]` as RFC 3339 (`YYYY-MM-DDThh:mm:ss[.f]±hh:mm`); any other text unchanged.
    static func spacedOffset(_ text: [UInt8]) -> [UInt8] {
        func digit(_ index: Int) -> Bool { index < text.count && (0x30 ... 0x39).contains(text[index]) }
        // The date, a space or T, and a time with its seconds.
        guard text.count > 19, (0 ..< 4).allSatisfy(digit), text[4] == 0x2D, digit(5), digit(6), text[7] == 0x2D,
            digit(8),
            digit(9), text[10] == 0x20 || text[10] == 0x54, digit(11), digit(12), text[13] == 0x3A, digit(14),
            digit(15),
            text[16] == 0x3A, digit(17), digit(18)
        else { return text }
        var end = 19
        if end < text.count, text[end] == 0x2E {
            end += 1
            guard digit(end) else { return text }
            while digit(end) { end += 1 }
        }
        // White space, then the offset.
        var sign = end
        while sign < text.count, text[sign] == 0x20 || text[sign] == 0x09 { sign += 1 }
        guard sign > end, sign < text.count, text[sign] == 0x2B || text[sign] == 0x2D else { return text }
        var position = sign + 1
        var hours: [UInt8] = []
        while digit(position), hours.count < 2 {
            hours.append(text[position])
            position += 1
        }
        var minutes: [UInt8] = [0x30, 0x30]
        if position < text.count, text[position] == 0x3A { position += 1 }
        if digit(position), digit(position + 1) {
            minutes = [text[position], text[position + 1]]
            position += 2
        }
        guard !hours.isEmpty, position == text.count else { return text }
        if hours.count == 1 { hours.insert(0x30, at: 0) }
        return Array(text[0 ..< 10]) + [0x54] + Array(text[11 ..< end]) + [text[sign]] + hours + [0x3A] + minutes
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
