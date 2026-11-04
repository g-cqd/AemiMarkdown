# AemiMarkdown

A Markdown parser for terminals and streams. It reads UTF-8 bytes and writes two flat tapes (blocks and inlines) that name source bytes by offset; it copies no
text, allocates nothing per node, parses a growing answer in time proportional to what was added, takes any bytes without failing, and bounds everything an
attacker could make large. CommonMark 0.31.2 plus the GitHub extensions: tables, strikethrough, autolinks, task lists and footnotes (the whole GFM extension
spec, 30 examples), and alerts (`> [!NOTE]`) and math (`$x$`, `$$x$$`), which GitHub renders but no spec describes. `MarkdownExtensions.github` turns all on,
`.gfm` only the specified ones.

**Status:** the parser is complete against both specifications: every CommonMark 0.31.2 example (652) and every GFM extension example (30) passes, and the
ratchet of known failures is empty. Compared with cmark 0.31.2 and cmark-gfm 0.29 on random inputs, the differences left are classified in
`DifferentialTests`: the references' own faults and spec-version differences, none owed. The reading API for renderers (top-level blocks with stable
identities, ADR-0002) is used by TerminalKit's Markdown renderer (`TerminalKitMarkdown`), which draws ask's assistant messages. Apple platforms only so far.

A document can also be **edited**: `MarkdownEditor.replace(_:with:)` takes bytes in place of a range anywhere and returns which blocks differ, in time that follows the edit (ADR-0003); each top-level block has a source range, a content hash and an ordinal, and `MarkdownFenceReader` reads a code block's language and lines without copying them.

```swift
import AemiMarkdown

var parser = MarkdownParser()
parser.append(Array("# Title\n\nSome **bold** text".utf8))
let document = parser.snapshot()      // closed blocks are final; the open one is provisional
for block in document.topLevelBlocks {
    // block.id is stable while the document grows; block.isFinal says it will not change again
    for event in document.events(of: block) { _ = event }
}
```

Documentation: the DocC catalog in `Sources/AemiMarkdown/AemiMarkdown.docc` (`AEMIMARKDOWN_DEV=1 swift package generate-documentation --target AemiMarkdown`).
Design: `docs/adr/`.

## Measured

Against swift-markdown `392b73b` (swift-cmark `a7ecfef`) on 17,001 real assistant messages (10.2 MB, from local agent session logs, not published), same machine, two runs
each, release builds, 2026-10-29 (`Benchmarks/MarkdownBench`, and ask's `development/research/probes/MarkdownBaselineProbe.swift.txt`):

| | swift-markdown | AemiMarkdown |
|---|---|---|
| Parse throughput | 14.8 MB/s | 200 to 203 MB/s; 272 to 278 MB/s with one parser reused |
| Allocations per KB | 252.5 | 35.2; 0.2 with one parser reused |
| A 100 KB answer streamed in 40-byte deltas, a snapshot after each | 4.07 to 4.10 s (full reparse) | 0.005 s (p50 1.6 µs per delta) |

The clocks differ: swift-markdown's probe reads `CLOCK_UPTIME_RAW` (wall time), AemiMarkdown's the thread's CPU time; the machine's load average was 1.8 to
1.9. The worst case is one paragraph of 100 KB with no line breaks: 148 to 150 µs per delta at p50, O(the paragraph) by design.

## Edits

On the public corpus (below), one byte put in a paragraph and taken out, instructions of the thread: 23 KB document 0.07 to 0.12 million, 1 MB 0.1 to 1.1 million, 5 MB 0.07 to 3.7 million (the end
to the start), against 1.8, 72.9 and 367 million for parsing the edited source whole. A warm editor allocates nothing for an edit in a paragraph. `MarkdownBench --edits` prints the position series.

## Corpus

Benchmarks and some tests run on public documents that are **not in the repository**: `Benchmarks/Corpus/manifest.json` lists 998 of them (URL, size, SHA-256) and
`python3 Benchmarks/Corpus/fetch.py setup` downloads them into `~/Library/Caches/AemiMarkdownCorpus`. Without them those tests are disabled, with the reason.
`MarkdownBench --corpus` parses them by size and prints instructions and cycles per byte (the figures that do not depend on what else the machine is doing).

## Licence

MIT (`LICENSE`), except these files, which are distributed with the tests and keep their own licences (see `Tests/AemiMarkdownTests/Fixtures/LICENSE.md`):

| File | Licence | Origin |
|---|---|---|
| `Tests/AemiMarkdownTests/Fixtures/commonmark-0.31.2.txt` | CC BY-SA 4.0 | the CommonMark specification 0.31.2, John MacFarlane |
| `Tests/AemiMarkdownTests/Fixtures/extensions.txt` | CC BY-SA 4.0 | the GFM extensions test file, Yuki Izumi (swift-cmark, `gfm`) |
| `Tests/AemiMarkdownTests/Fixtures/cmark-pathological_tests.py` | BSD-2-Clause | cmark |

They are test data: nothing in `Sources/` is derived from them, and their terms apply to them and their adaptations, not to the rest of the repository.
