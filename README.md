# AemiMarkdown

A Markdown parser for terminals and streams. It reads UTF-8 bytes and writes two flat tapes (blocks and inlines) that name source bytes by offset; it copies no
text, allocates nothing per node, parses a growing answer in time proportional to what was added, takes any bytes without failing, and bounds everything an
attacker could make large. CommonMark 0.31.2 plus the GitHub extensions: tables, strikethrough, autolinks, task lists and footnotes (the whole GFM extension spec, 30 examples), and alerts (`> [!NOTE]`) and math (`$x$`, `$$x$$`), which GitHub renders but no spec describes. `MarkdownExtensions.github` turns all on, `.gfm` only the specified ones.

**Status: under construction.** The design is `docs/adr/0001-*.md`. Measured claims are made only where a benchmark exists; see `AGENTS.md`.

```swift
import AemiMarkdown

var parser = MarkdownParser()
parser.append(Array("# Title\n\nSome **bold** text".utf8))
let document = parser.snapshot()      // closed blocks are final; the open one is provisional
```
