import Foundation
import Testing

@testable import AemiMarkdown

/// The parser against a reference implementation, on inputs that no hand wrote (ADR-0001, decision 6). It runs when `AEMIMARKDOWN_DIFFERENTIAL` names an
/// NDJSON file made by `Scripts/reference-html.py`, and `AEMIMARKDOWN_DIFFERENTIAL_MODE` is `core` (CommonMark alone, the extensions off) or `ext` (all on);
/// `AEMIMARKDOWN_DIFFERENTIAL_REPORT` names a file that receives the first mismatches.
///
/// Known differences from cmark 0.31.2, both cmark's and not followed (2026-10-29: 4 of 5,000 and 2 of 20,000 random inputs, all of these two kinds):
/// - a link reference definition whose title line has text after it keeps the title in cmark (`[foo]: /url` then `(title) ok`); the spec says such a
///   definition "has no title";
/// - in a fenced code block's info string cmark decodes entities before backslash escapes, so `\&amp;` reads `&`; in text it reads `&amp;`, and
///   AemiMarkdown reads both as text does.
///
/// Against cmark-gfm 0.29.0.gfm.13 (`ext`, 2026-10-29, 5,000 random inputs, seed 3): 278 differ after the task-marker fix, and none is a fault in an extension
/// as the GFM spec describes it:
/// - 150: cmark-gfm makes no bare autolink while a `[` or `![` is open, even one that never closes and so is plain text;
/// - 68: cmark-gfm checks a `[ ]` item when the item holds a later `[x]`;
/// - 44: the same input renders as cmark 0.31.2 renders it with the extensions off (cmark-gfm follows spec 0.29, and its task list extension takes the
///   marker at the block level, which ends a lazy continuation);
/// - 15, owed: a bare link runs to white space or `<` (GFM 6.9), through a `\*` or a backtick; AemiMarkdown links bare URLs after the inline phase,
///   where an escape or a code span has already split the text, so its link stops there;
/// - 1: a tab split across container indentation on a lazy line inside a code span, which cmark turns into spaces and a source range cannot hold.
@Suite("The parser agrees with a reference implementation on generated and real input")
struct DifferentialTests {
    static let path = ProcessInfo.processInfo.environment["AEMIMARKDOWN_DIFFERENTIAL"]

    private struct Record: Decodable {
        var t: String
        var h: String
    }

    @Test(.enabled(if: path != nil))
    func `every input renders as the reference renders it`() throws {
        let path = try #require(Self.path)
        let environment = ProcessInfo.processInfo.environment
        let extensions: MarkdownExtensions = environment["AEMIMARKDOWN_DIFFERENTIAL_MODE"] == "ext" ? .gfm : []
        let decoder = JSONDecoder()
        var total = 0
        var mismatches: [String] = []
        for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
            let record = try decoder.decode(Record.self, from: Data(line.utf8))
            total += 1
            let document = MarkdownParser.parse(Array(record.t.utf8), extensions: extensions)
            #expect(TapeValidator.problem(in: document) == nil)
            let html = SpecHTMLRenderer.html(of: document)
            if html != record.h {
                mismatches.append(
                    "## \(total)\n\(record.t.debugDescription)\nreference \(record.h.debugDescription)\nactual    \(html.debugDescription)\n"
                )
            }
        }
        if let report = environment["AEMIMARKDOWN_DIFFERENTIAL_REPORT"] {
            try mismatches.prefix(400).joined(separator: "\n").write(toFile: report, atomically: true, encoding: .utf8)
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(total) inputs differ from the reference")
    }
}
