import AemiTestKit
import Testing

@testable import AemiMarkdown

private let isDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()

/// An edit that reads its own region allocates nothing once the editor is warm (ADR-0003): the arrays it needs are kept from one edit to the next.
/// The ceilings describe the optimized build (see `AllocationTests`).
@Suite(
    "A warm editor does not allocate for an edit",
    .serialized,
    .disabled(if: isDebugBuild, "the ceilings describe the optimized build; run them with -c release"),
    .enabled(if: allocationCountingAvailable, "allocations are counted on Darwin only, and not under a sanitizer")
)
struct EditorAllocationTests {
    static let document = Array(
        String(
            repeating:
                "A paragraph with *emphasis*, `code` and a [link](https://example.com/page).\n\n- one\n- two\n\n> quote\n\n",
            count: 200
        )
        .utf8
    )

    /// The ceiling for an edit in a block of this kind: when the block after the region's end starts with a list or a quote open, the look at its first line
    /// copies a little of the reader's state (a few arrays); when nothing is open it is a look at the bytes.
    @Test(arguments: [(NodeKind.paragraph, 0), (NodeKind.list, 16), (NodeKind.blockQuote, 16)])
    func `a byte put in and taken out allocates nothing in a paragraph and a little elsewhere`(
        kind: NodeKind,
        ceiling: Int
    ) throws {
        var editor = MarkdownEditor(Self.document)
        let blocks = Array(editor.document.topLevelBlocks)
        for ordinal in [100, 101, 102, 301] where blocks[ordinal].node.kind == kind {
            let position = blocks[ordinal].sourceRange.lowerBound + 1
            let byte: [UInt8] = [UInt8(ascii: "x")]
            for _ in 0 ..< 5 {  // grow every buffer
                editor.replace(position ..< position, with: byte)
                editor.replace(position ..< (position + 1), with: [])
            }
            let allocations = try #require(
                mallocDelta {
                    editor.replace(position ..< position, with: byte)
                    editor.replace(position ..< (position + 1), with: [])
                }
            )
            #expect(!editor.lastEditParsedWhole)
            #expect(allocations <= ceiling, "two edits in a \(kind) allocated \(allocations) times")
        }
    }
}
