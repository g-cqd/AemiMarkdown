internal import AemiMarkdown
internal import Foundation

/// Safe, inert HTML tags that `MarkdownLookKit` interprets for both the HTML page and the native SwiftUI view (ADR-0004):
///
/// - Inline `<br>` (including `<br/>`, `<br />`, any ASCII case, no attributes) becomes a line break in prose and table cells.
/// - Block `<details>` (with optional `open` attribute), `<summary>…</summary>`, and `</details>` become a collapsible
///   disclosure panel whose body renders Markdown normally.
///
/// Every other HTML tag, attribute, or malformed construct stays literal text — nothing from the document is ever echoed
/// unescaped into HTML or allowed to carry arbitrary attributes or scripts.
@available(macOS 26.0, *)
enum SafeHTML {
    /// A line break tag (`<br>`, `<br/>`, `<br />`, any ASCII case, no attributes).
    static func isLineBreak(_ bytes: ArraySlice<UInt8>) -> Bool {
        var i = bytes.startIndex
        let end = bytes.endIndex
        guard end - i >= 4, bytes[i] == 0x3C else { return false }
        i += 1
        guard lower(bytes[i]) == 0x62, lower(bytes[i + 1]) == 0x72 else { return false }
        i += 2
        while i < end, isSpace(bytes[i]) { i += 1 }
        if i < end, bytes[i] == 0x2F { i += 1 }
        return i + 1 == end && bytes[i] == 0x3E
    }

    /// A line break tag from a string slice.
    static func isLineBreak(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return isLineBreak(bytes[...])
    }

    /// What a recognized HTML block (starting with `<details`, `</details>`, `<summary`, or `</summary>`) holds.
    /// Returns nil when the HTML block is not a disclosure construct (so the caller renders it verbatim as HTML source).
    enum Directive: Equatable {
        /// `<details>` or `<details open>` (the boolean says whether `open` was set).
        case openDetails(open: Bool)
        /// `</details>`.
        case closeDetails
        /// A complete `<summary>…</summary>` label (raw Markdown/inline text inside the tags, trimmed).
        case summary(String)
        /// `<summary>` opened without its closing `</summary>` in this block (the closing tag may appear after a blank line).
        case openSummary
        /// `</summary>`.
        case closeSummary
        /// Non-tag Markdown content inside the same CommonMark condition-6 HTML block (no blank line after a tag).
        case markdown(String)
    }

    /// Parses an HTML block's joined text into disclosure directives, or returns nil if the block is ordinary raw HTML.
    ///
    /// - Complexity: O(raw.utf8.count), single linear pass.
    static func parseBlock(_ raw: String) -> [Directive]? {
        var scanner = BlockScanner(bytes: Array(raw.utf8))
        return scanner.parse()
    }

    /// Rewrites simple safe inline HTML tags inside `<summary>` (`<code>`, `<strong>`/`<b>`, `<em>`/`<i>`) into
    /// Markdown so both HTML and native views render styled summaries without trusting arbitrary raw HTML.
    static func summaryMarkdown(_ raw: String) -> String {
        var result = ""
        let bytes = Array(raw.utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x3C, let (replacement, after) = matchSummaryInlineTag(in: bytes, from: i) {
                result += replacement
                i = after
                continue
            }
            let next = nextScalarIndex(in: bytes, from: i)
            result += String(decoding: bytes[i ..< next], as: UTF8.self)
            i = next
        }
        return result
    }

    private static func matchSummaryInlineTag(in bytes: [UInt8], from start: Int) -> (String, Int)? {
        if let afterOpen = matchSimpleTag("code", closing: false, in: bytes, from: start),
            let closeRange = findClosingSimpleTag("code", in: bytes, from: afterOpen)
        {
            let inner = decodeBasicEntities(
                String(decoding: bytes[afterOpen ..< closeRange.lowerBound], as: UTF8.self)
            )
            let fence = inner.contains("`") ? "`` " : "`"
            let closeFence = inner.contains("`") ? " ``" : "`"
            return (fence + inner + closeFence, closeRange.upperBound)
        }
        for (names, marker) in [(["strong", "b"], "**"), (["em", "i"], "*")] {
            for name in names {
                if let after = matchSimpleTag(name, closing: false, in: bytes, from: start)
                    ?? matchSimpleTag(name, closing: true, in: bytes, from: start)
                {
                    return (marker, after)
                }
            }
        }
        return nil
    }
}

/// Linear scanner splitting an HTML block into `SafeHTML.Directive` items.
@available(macOS 26.0, *)
extension SafeHTML {
    private struct BlockScanner {
        let bytes: [UInt8]
        var directives: [Directive] = []
        var index = 0
        var recognizedAny = false
        var pendingText = ""

        mutating func parse() -> [Directive]? {
            while index < bytes.count {
                let lineEnd = nextLineEnd(in: bytes, from: index)
                let nextIndex = lineEnd < bytes.count ? lineEnd + 1 : bytes.count
                if scanTagLine(lineEnd: lineEnd, nextIndex: nextIndex) { continue }
                if !recognizedAny { return nil }
                pendingText += String(decoding: bytes[index ..< lineEnd], as: UTF8.self)
                if lineEnd < bytes.count { pendingText.append("\n") }
                index = nextIndex
            }
            guard recognizedAny else { return nil }
            flushPending()
            return directives
        }

        private mutating func scanTagLine(lineEnd: Int, nextIndex: Int) -> Bool {
            let lineStartPos = trimLeadingSpaces(in: bytes, from: index, to: lineEnd)
            guard lineStartPos < lineEnd, bytes[lineStartPos] == 0x3C else { return false }
            var pos = lineStartPos
            var matchedOnLine = false
            while pos < lineEnd {
                pos = trimLeadingSpaces(in: bytes, from: pos, to: lineEnd)
                guard pos < lineEnd else { break }
                guard let step = matchOneTag(from: pos, lineEnd: lineEnd) else {
                    if matchedOnLine {
                        appendTrailingText(from: pos, to: lineEnd)
                        pos = lineEnd
                    }
                    break
                }
                matchedOnLine = true
                if let jumpedTo = step.multilineNextIndex {
                    index = jumpedTo
                    return true
                }
                pos = step.nextPos
            }
            guard matchedOnLine else { return false }
            index = nextIndex
            return true
        }

        private struct TagStep {
            var nextPos: Int
            var multilineNextIndex: Int?
        }

        private mutating func matchOneTag(from pos: Int, lineEnd: Int) -> TagStep? {
            if let (isOpen, after) = matchOpenDetails(bytes, from: pos, to: lineEnd) {
                flushPending()
                directives.append(.openDetails(open: isOpen))
                recognizedAny = true
                return TagStep(nextPos: after)
            }
            if let after = matchClosingTag("details", in: bytes, from: pos, to: lineEnd) {
                flushPending()
                directives.append(.closeDetails)
                recognizedAny = true
                return TagStep(nextPos: after)
            }
            if let afterOpen = matchOpenSummary(bytes, from: pos, to: lineEnd) {
                flushPending()
                recognizedAny = true
                return consumeSummary(from: afterOpen, lineEnd: lineEnd)
            }
            if let after = matchClosingTag("summary", in: bytes, from: pos, to: lineEnd) {
                flushPending()
                directives.append(.closeSummary)
                recognizedAny = true
                return TagStep(nextPos: after)
            }
            return nil
        }

        private mutating func consumeSummary(from afterOpen: Int, lineEnd: Int) -> TagStep {
            guard let closeRange = findClosingSummary(in: bytes, from: afterOpen, to: bytes.count) else {
                directives.append(.openSummary)
                return TagStep(nextPos: afterOpen)
            }
            let inner = String(decoding: bytes[afterOpen ..< closeRange.lowerBound], as: UTF8.self)
            directives.append(.summary(inner.trimmingCharacters(in: .whitespacesAndNewlines)))
            if closeRange.upperBound <= lineEnd { return TagStep(nextPos: closeRange.upperBound) }
            let endOfCloseLine = nextLineEnd(in: bytes, from: closeRange.upperBound)
            appendTrailingText(from: closeRange.upperBound, to: endOfCloseLine)
            let jumped = endOfCloseLine < bytes.count ? endOfCloseLine + 1 : bytes.count
            return TagStep(nextPos: endOfCloseLine, multilineNextIndex: jumped)
        }

        private mutating func appendTrailingText(from start: Int, to end: Int) {
            let rest = String(decoding: bytes[start ..< end], as: UTF8.self)
            if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pendingText += rest + "\n" }
        }

        private mutating func flushPending() {
            if !pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                directives.append(.markdown(pendingText))
            }
            pendingText = ""
        }
    }
}

/// Low-level ASCII tag and attribute matchers for ``SafeHTML``.
@available(macOS 26.0, *)
extension SafeHTML {
    /// Matches `<details>` or `<details ...>` (ignoring unknown attributes safely; recognizes the boolean `open`
    /// attribute). Returns `(isOpen, endIndex)`.
    static func matchOpenDetails(_ bytes: [UInt8], from start: Int, to end: Int) -> (Bool, Int)? {
        guard let afterName = matchTagPrefix("details", closing: false, in: bytes, from: start, to: end) else {
            return nil
        }
        return scanAttributes(in: bytes, from: afterName, to: end, trackOpen: true)
    }

    /// Matches `<summary>` (with optional attributes, all ignored safely). Returns the index after `>`.
    static func matchOpenSummary(_ bytes: [UInt8], from start: Int, to end: Int) -> Int? {
        guard let afterName = matchTagPrefix("summary", closing: false, in: bytes, from: start, to: end) else {
            return nil
        }
        return scanAttributes(in: bytes, from: afterName, to: end, trackOpen: false)?.1
    }

    private static func scanAttributes(
        in bytes: [UInt8],
        from start: Int,
        to end: Int,
        trackOpen: Bool
    ) -> (Bool, Int)? {
        var i = start
        var isOpen = false
        while i < end {
            let beforeSpace = i
            while i < end, isSpace(bytes[i]) { i += 1 }
            guard i < end else { return nil }
            if bytes[i] == 0x3E { return (isOpen, i + 1) }
            guard i > beforeSpace else { return nil }
            let attrStart = i
            while i < end, isAttrNameChar(bytes[i]) { i += 1 }
            guard i > attrStart else { return nil }
            let isOpenAttr = trackOpen && equalsIgnoringCase(bytes[attrStart ..< i], "open")
            let afterAttr = i
            while i < end, isSpace(bytes[i]) { i += 1 }
            if i < end, bytes[i] == 0x3D {
                i += 1
                while i < end, isSpace(bytes[i]) { i += 1 }
                guard i < end, let afterVal = skipAttributeValue(bytes, from: i, to: end) else { return nil }
                if isOpenAttr { isOpen = true }
                i = afterVal
            } else {
                if isOpenAttr { isOpen = true }
                i = afterAttr
            }
        }
        return nil
    }

    static func matchClosingTag(_ name: String, in bytes: [UInt8], from start: Int, to end: Int) -> Int? {
        guard var i = matchTagPrefix(name, closing: true, in: bytes, from: start, to: end) else { return nil }
        while i < end, isSpace(bytes[i]) { i += 1 }
        guard i < end, bytes[i] == 0x3E else { return nil }
        return i + 1
    }

    static func matchSimpleTag(_ name: String, closing: Bool, in bytes: [UInt8], from start: Int) -> Int? {
        guard var i = matchTagPrefix(name, closing: closing, in: bytes, from: start, to: bytes.count) else {
            return nil
        }
        while i < bytes.count, isSpace(bytes[i]) { i += 1 }
        guard i < bytes.count, bytes[i] == 0x3E else { return nil }
        return i + 1
    }

    static func findClosingSummary(in bytes: [UInt8], from start: Int, to end: Int) -> Range<Int>? {
        var i = start
        while i < end {
            if bytes[i] == 0x3C, let after = matchClosingTag("summary", in: bytes, from: i, to: end) {
                return i ..< after
            }
            i += 1
        }
        return nil
    }

    static func findClosingSimpleTag(_ name: String, in bytes: [UInt8], from start: Int) -> Range<Int>? {
        var i = start
        while i < bytes.count {
            if bytes[i] == 0x3C, let after = matchSimpleTag(name, closing: true, in: bytes, from: i) {
                return i ..< after
            }
            i += 1
        }
        return nil
    }

    static func decodeBasicEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return
            text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func matchTagPrefix(
        _ name: String,
        closing: Bool,
        in bytes: [UInt8],
        from start: Int,
        to end: Int
    ) -> Int? {
        var i = start
        guard i < end, bytes[i] == 0x3C else { return nil }
        i += 1
        if closing {
            guard i < end, bytes[i] == 0x2F else { return nil }
            i += 1
        }
        let target = Array(name.utf8)
        guard i + target.count <= end else { return nil }
        for offset in 0 ..< target.count where lower(bytes[i + offset]) != target[offset] { return nil }
        i += target.count
        if i < end, isTagNameChar(bytes[i]) { return nil }
        return i
    }

    private static func skipAttributeValue(_ bytes: [UInt8], from start: Int, to end: Int) -> Int? {
        let quote = bytes[start]
        if quote == 0x22 || quote == 0x27 {
            var i = start + 1
            while i < end, bytes[i] != quote { i += 1 }
            return i < end ? i + 1 : nil
        }
        var i = start
        while i < end, !isSpace(bytes[i]), bytes[i] != 0x3E, bytes[i] != 0x3C, bytes[i] != 0x22, bytes[i] != 0x27,
            bytes[i] != 0x3D, bytes[i] != 0x60
        { i += 1 }
        return i > start ? i : nil
    }

    static func nextLineEnd(in bytes: [UInt8], from start: Int) -> Int {
        var i = start
        while i < bytes.count, bytes[i] != 0x0A { i += 1 }
        return i
    }

    static func trimLeadingSpaces(in bytes: [UInt8], from start: Int, to end: Int) -> Int {
        var i = start
        while i < end, isSpace(bytes[i]) { i += 1 }
        return i
    }

    static func nextScalarIndex(in bytes: [UInt8], from start: Int) -> Int {
        let lead = bytes[start]
        let step = lead < 0x80 ? 1 : (lead < 0xE0 ? 2 : (lead < 0xF0 ? 3 : 4))
        return Swift.min(start + step, bytes.count)
    }

    static func lower(_ b: UInt8) -> UInt8 { b >= 0x41 && b <= 0x5A ? b + 0x20 : b }
    static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A }

    static func isTagNameChar(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x2D
    }

    static func isAttrNameChar(_ b: UInt8) -> Bool { isTagNameChar(b) || b == 0x5F || b == 0x3A || b == 0x2E }

    static func equalsIgnoringCase(_ slice: ArraySlice<UInt8>, _ target: String) -> Bool {
        let targetBytes = Array(target.utf8)
        guard slice.count == targetBytes.count else { return false }
        return zip(slice, targetBytes).allSatisfy { lower($0) == $1 }
    }
}
