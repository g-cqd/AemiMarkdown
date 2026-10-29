# ``AemiMarkdown``

A Markdown parser for terminals and streams: UTF-8 bytes in, two flat tapes out, incremental, bounded, and never failing.

## Overview

AemiMarkdown reads CommonMark 0.31.2 and the GitHub extensions (tables, strikethrough, autolinks, task lists, footnotes), plus GitHub's alerts and
math. It writes two flat tapes, blocks and inlines, whose leaves name source bytes by offset: it copies no text and allocates nothing per node. A
growing document, such as a model's answer arriving in pieces, is parsed in time proportional to what was added. Any bytes give a document; what an
attacker could make large is bounded by ``MarkdownLimits``, and what was unusual is reported in ``MarkdownDocument/diagnostics``.

```swift
import AemiMarkdown

let document = MarkdownParser.parse(Array("# Title\n\nSome **bold** text.\n".utf8))
for event in document.events {
    switch event {
        case .enter(let node): print("enter", node.kind)
        case .exit(let node): print("exit", node.kind)
        case .leaf(let node): print("leaf", node.kind, node.range)
    }
}
```

## Topics

### Parsing

- ``MarkdownParser``
- ``MarkdownExtensions``
- ``MarkdownLimits``
- ``MarkdownDiagnostics``

### Reading a document

- ``MarkdownDocument``
- ``MarkdownEvents``
- ``MarkdownEvent``
- ``MarkdownNode``
- ``NodeKind``
- ``ListFlags``

### Streaming and rendering

- <doc:Streaming>
- <doc:RenderingBlockByBlock>
- ``MarkdownBlock``
- ``MarkdownBlocks``
