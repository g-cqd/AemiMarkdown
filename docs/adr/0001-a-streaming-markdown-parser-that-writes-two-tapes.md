---
status: accepted
date: 2026-10-25
---

# 0001 — A streaming Markdown parser that writes two flat tapes and never fails

## Context

ask draws an assistant's answer as Markdown while it streams in (ask roadmap 0065). Probes, 2026-10-25 (ask diary 2026-10-25-01):

- swift-markdown (cmark-gfm): 10.3 MB/s, 270 allocations per KB, and 4.94 s of parsing to stream a 100 KB answer in 40-byte deltas, because every
  delta reparses the whole text (1.7 ms at p50 and 4.5 ms at p99 per delta, growing with length).
- glow 3.0.0: 100 KB/s; nested quotes 100 deep did not finish in 30 s; a raw OSC 52 passed through to the terminal.
- 19,840 real assistant messages: inline code, strong, bullet lists, headings, fences, links (mostly file paths), tables; list depth at most 4;
  no images, task lists, strikethrough, footnotes, control bytes or Mermaid.

## Decision

1. **A new package, `AemiMarkdown`**, in its own repository like AemiJSON. It reads UTF-8 bytes and writes tapes. It owns no rendering.
2. **Two tapes of `UInt64` slots**, each slot packed by Aemi's `TapeSlot` (tag 4 bits, aux 28 bits, low 32 bits), preorder, no node objects.
   - The **block tape** holds containers and leaf blocks. A container's `low` is the index after its subtree (O(1) skip), patched when it closes.
   - The **inline tape** holds the inlines of every leaf block that has any, one contiguous run per leaf. The leaf's slot records the run's start and
     length. Inlines are parsed in a second phase, which is why a reference definition later in the document can still resolve an earlier link.
   - Every slot names source bytes by offset and length. Text is never copied. A backslash escape splits a text run around the backslash. An entity is a
     leaf that names its source and is decoded on request (`MarkdownDocument.decode`). A tab that a list or code block consumes only in part leaves
     virtual spaces, a leaf with a count.
   - A source over 4 GiB, or a leaf over 4 MiB, does not occur: `MarkdownLimits` is far below both, and a long run splits.
3. **The block phase is line-oriented and incremental.** `append(_:)` consumes complete lines and keeps a partial line; the open containers are a stack.
   It works on each new line only. A closed block is final.
4. **The inline phase runs when a leaf closes**, and for the open leaf on demand at `snapshot()`, into a tail of the inline tape that is cut off and
   rewritten each time. The cost of a delta is O(delta) for blocks plus O(the open leaf) for its inlines. A fenced code block has no inlines, so a long one costs
   O(delta). Whole-document parsing (`parse(_:)`) defers every inline run to the end, so reference definitions apply as CommonMark says. A streamed document
   applies a definition only to blocks that close after it. That is the one place streaming and batch results differ, and it is tested.
5. **It never fails.** Every byte sequence gives a document. Invalid UTF-8, NUL and control bytes are text; `MarkdownDocument.diagnostics` says that they occurred
   (found with Aemi's SIMD scans), so a renderer can neutralise them. A construct that exceeds a limit in `MarkdownLimits` (container nesting, inline nesting,
   line length, delimiter work, table columns, document size) is kept as plain text, and `diagnostics` names the limit. No recursion: block nesting is an explicit stack and inline nesting an
   explicit stack; every loop has a bound.
6. **Conformance.** CommonMark 0.31.2 (652 examples) and every extension of the GFM specification (tables, strikethrough, autolinks, tag filter, task lists, footnotes), all 30 examples. Alerts and math are GitHub's, not in the spec, so they are tested against GitHub's documentation, not against a reference. The spec files are the
   tests, compared as HTML through a renderer that lives in the test target. A **ratchet** lists the examples that fail; it shrinks and never gains an entry,
   and an example that passes while listed fails the suite, so the list cannot go stale. Raw HTML passes through as text for a terminal: it is parsed, not interpreted.
7. **Dependencies, by what each does.**

| Tool | Use | Where |
|---|---|---|
| Aemi `AemiKernel` | `TapeSlot`, `ASCII`, `XXH64` (reference-label hashing), `UTF8Validation`, `ByteBufferPool` | shipped |
| Aemi `AemiKernels` | SIMD scans over whole blocks: next special byte, control and invalid-UTF-8 detection (ADR-0014 made them fast at 80 bytes) | shipped |
| Aemi `AemiUnicode` case folding | reference-label matching, which CommonMark defines on the Unicode case fold | shipped, when the first non-ASCII label needs it |
| Aemi `AemiTestKit` | allocation ceilings (`CAemiTestKitMalloc`) in every suite | tests |
| AemiRegex | the spec defines raw-HTML tags, autolinks and email addresses by regular grammars; the hand-written byte scanners are checked against those grammars, differentially, on generated and mutated inputs | tests, behind `AEMIMARKDOWN_DEV`, by path (it has no remote yet) |
| AemiJSON | generating the entity table from the WHATWG `entities.json` in a tool outside the package; reading corpus reports | `Plugins/GenerateEntities` (a separate package that the library does not depend on; `Plugins/` is where the shared lint configuration expects tooling) |
| Swift standard library | `Unicode.Scalar.Properties.generalCategory` for punctuation and whitespace outside ASCII, which the flanking rules need | shipped; a table from AemiRegex's generated Unicode data replaces it only if a measurement asks |

   AemiRegex is not on the parse path: its API takes an `Array`, and a search costs more than a scan of an 80-byte line. *Stated from reading the
   signature, to be measured if the question comes back.*
8. **Public surface** is small: `MarkdownParser` (a struct that owns its source and tapes and reuses its buffers), `MarkdownDocument` (a borrowed view with a
   non-recursive event walker and `decode`), `MarkdownLimits`, `MarkdownDiagnostics`, `NodeKind`.

## Consequences

- Rendering (ask's terminal renderer, a test HTML renderer) is a consumer of events, so the parser has no opinion about colour, width or links.
- A consumer that needs the exact CommonMark result for an unterminated construct while streaming sees a provisional tail that can change on the next
  `append`; closed blocks never change.
- The spec's HTML output is reproduced by a test renderer, so each failing example is a parser fault or a renderer fault. The ratchet file records which, with a reason per group.
- Goals, to be met and measured against the swift-markdown baseline, not assumed: cost per delta independent of the answer's length; no allocation per node;
  an order of magnitude more throughput. Until measured, no performance claim is made.
