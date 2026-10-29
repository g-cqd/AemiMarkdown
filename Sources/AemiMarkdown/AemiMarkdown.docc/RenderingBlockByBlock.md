# Rendering block by block

Lay each top-level block out once, and only the block that can still change again.

## Overview

``MarkdownDocument/topLevelBlocks`` lists the top-level blocks. Each ``MarkdownBlock`` has an ``MarkdownBlock/id`` that does not change while the
document grows, so a renderer can cache what it drew for a block under that identity, and ``MarkdownBlock/isFinal`` says that no later input can change
the block. ``MarkdownDocument/events(of:)`` walks one block. In this sketch `layOut` is the renderer's own:

```swift
var cache: [Int: [String]] = [:]   // rows drawn per block

func draw(_ document: MarkdownDocument) -> [String] {
    var rows: [String] = []
    for block in document.topLevelBlocks {
        if let kept = cache[block.id] {
            rows += kept
            continue
        }
        let drawn = layOut(document.events(of: block), source: document.source)
        if block.isFinal { cache[block.id] = drawn }
        rows += drawn
    }
    return rows
}
```

A block is final when it has closed in the parser. A snapshot parses a partial last line as if the input ended there, and that can close a block the
complete line would not: `- foo` followed by a lone `*` reads as two lists, but the `**` that follows makes the line a continuation of `foo`. So the
blocks a snapshot shows closing on its last, partial line are not final yet. A heading or a thematic break becomes final when the next line arrives.

The identity is the block's place on the block tape. The same document streamed in pieces and parsed whole gives the same identities, except where a
link reference definition changes how a block parses (see <doc:Streaming>).
