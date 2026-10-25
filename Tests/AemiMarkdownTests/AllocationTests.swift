import AemiTestKit
import Testing

@testable import AemiMarkdown

/// A parser that is used again allocates nothing for a document no larger than one it has parsed: the buffers it grew are kept, and nothing is allocated per node
/// (ADR-0001, goals). `mallocDelta` counts the allocations of the calling thread, so the work is synchronous and on this thread.
@Suite("A reused parser does not allocate", .serialized)
struct AllocationTests {
    static let document = Array(
        """
        # A heading with `code` and **bold**

        A paragraph with *emphasis*, a [link](https://example.com/a "title"), an ![image](/i.png), <b>inline HTML</b>,
        a bare https://example.com/b and www.example.com, an entity &amp; and a hard break\\
        and a soft break.

        - one
        - two
          - nested **item**
        1. first
        2. second

        > a quote
        > with two lines

        | a | b |
        |---|:-:|
        | 1 | `2` |

        ```swift
        let x = 1
        ```

        Text with ~~strikethrough~~ and a [broken](/url link.
        ***
        """
        .utf8)

    @Test func `parsing a document again allocates nothing`() throws {
        var parser = MarkdownParser()
        for _ in 0 ..< 3 {  // grow every buffer
            parser.reset()
            parser.append(Self.document)
            parser.finish()
        }
        let allocations = try #require(
            mallocDelta {
                parser.reset()
                parser.append(Self.document)
                parser.finish()
            })
        #expect(allocations == 0, "a reused parser allocated \(allocations) times")
    }

    /// Every construct on its own, so that a new allocation names the construct that made it.
    @Test(arguments: [
        "just some plain text\n", "# h\n", "a *b* **c** d\n", "a `b` c\n", "a [b](/u \"t\") c\n", "![a](/b)\n",
        "<https://a.b/c>\n", "<a@b.co>\n",
        "see https://example.com/b now\n", "see www.example.com now\n", "a &amp; b\n", "a \\* b\n", "a <b>x</b> c\n",
        "a\\\nb\n", "a\nb\n", "- a\n- b\n",
        "1. a\n2. b\n", "- a\n  - b\n", "> a\n", "```swift\nlet x\n```\n", "    code\n", "***\n",
        "| a | b |\n|---|---|\n| 1 | 2 |\n", "~~a~~\n",
        "<div>\nx\n</div>\n", "a\n===\n", "a <!-- c --> b\n", "mail a@b.co now\n"
    ])
    func `each construct, parsed again, allocates nothing`(markdown: String) throws {
        var parser = MarkdownParser()
        let bytes = Array(markdown.utf8)
        for _ in 0 ..< 3 {
            parser.reset()
            parser.append(bytes)
            parser.finish()
        }
        let allocations = try #require(
            mallocDelta {
                parser.reset()
                parser.append(bytes)
                parser.finish()
            })
        #expect(allocations == 0, "\(markdown.debugDescription) allocated \(allocations) times")
    }

    /// The one allocation a definition makes is its key, the normalized label in the table.
    @Test func `a link reference definition allocates its key, once`() throws {
        var parser = MarkdownParser()
        let bytes = Array("[ref]: /url \"title\"\n\nText with [ref] and [Ref].\n".utf8)
        for _ in 0 ..< 3 {
            parser.reset()
            parser.append(bytes)
            parser.finish()
        }
        let allocations = try #require(
            mallocDelta {
                parser.reset()
                parser.append(bytes)
                parser.finish()
            })
        #expect(allocations == 1)
    }

    @Test func `streaming the same document in pieces without snapshots allocates nothing`() throws {
        var parser = MarkdownParser()
        for _ in 0 ..< 3 {
            parser.reset()
            for piece in stride(from: 0, to: Self.document.count, by: 40) {
                parser.append(Array(Self.document[piece ..< Swift.min(piece + 40, Self.document.count)]))
            }
            parser.finish()
        }
        let pieces = stride(from: 0, to: Self.document.count, by: 40)
            .map { Array(Self.document[$0 ..< Swift.min($0 + 40, Self.document.count)]) }
        let allocations = try #require(
            mallocDelta {
                parser.reset()
                for piece in pieces { parser.append(piece) }
                parser.finish()
            })
        #expect(allocations == 0, "streaming without snapshots allocated \(allocations) times")
    }
}
