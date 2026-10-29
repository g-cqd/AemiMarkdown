# Streaming

Parse a document while it arrives, and read it at any moment.

## Overview

``MarkdownParser/append(_:)`` parses every complete line it is given and keeps a partial last line for later. ``MarkdownParser/snapshot()`` returns the
document as it stands: blocks that have closed are final, and the open ones are read as if the input ended there. The cost of a snapshot is that of the
open top-level block, not of the document. ``MarkdownParser/finish()`` ends the document.

```swift
var parser = MarkdownParser()
parser.append(Array("# Title\n\nStill being wri".utf8))
let partial = parser.snapshot()   // a heading and a provisional paragraph
parser.append(Array("tten.\n".utf8))
parser.finish()
let finished = parser.snapshot()
```

A snapshot shares storage with the parser, copy-on-write: read it and let it go before the next append, or the append copies the closed part once.

### The one difference from a whole parse

A link reference definition applies to every link when a document is parsed whole (``MarkdownParser/parse(_:extensions:limits:)``). While streaming it
reaches only the blocks that close after it, because a closed block is never parsed again.
