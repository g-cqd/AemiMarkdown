---
status: accepted
date: 2026-10-29
---

# 0002 — Top-level blocks have stable identities, and finality comes from the parser, not the snapshot

## Context

A renderer of a streamed answer (TerminalKit roadmap 0022, ask roadmap 0065) must lay a block out once and keep its rows, and lay out again only
what can still change; otherwise drawing costs the document, not the delta, and ask's memory work (ask 0088, TerminalKit 0023) cannot drop and
rebuild rows per block. ADR-0001 made closed blocks final but gave a reader no way to see which blocks those are, nor a name to cache them by.
`MarkdownEvents` walks the whole document.

## Decision

1. `MarkdownDocument.topLevelBlocks` lists the top-level blocks as `MarkdownBlock` values: `id`, `node` and `isFinal`. `events(of:)` walks one
   block, so a renderer reads only the block it lays out. Walking every block in turn is walking the document (tested on every spec example).
2. **The identity is the block's index on the block tape.** Indices are global and a closed block never moves, so the same block has the same
   identity in every later snapshot and in the finished document; a document streamed in pieces gives the identities of the same document
   parsed whole (tested on the spec examples without a reference definition, the one documented difference of ADR-0001).
3. **A block is final when it has closed in the parser**: it lies before the first open top-level block of the parser itself, or the document is
   finished. Not "every block but the last of the snapshot": a snapshot parses a partial last line as if the input ended there, and that can close a
   block the complete line would not (`- foo\n*` starts a second list; `- foo\n**` continues the paragraph). The first version made that mistake and
   the property test below failed on 19 spec examples. The boundary is read before the provisional copy is made, so it costs one integer.
4. Consequences: a one-line block (a heading, a thematic break) is not final until the next line arrives, as it stays open in cmark's model; a list
   followed by an open paragraph is final once a complete line has closed it, before the tape commits it.

## Evidence

`BlockIdentityTests`: every spec example streamed one byte at a time, a snapshot after each byte; a block once reported final must come back with the
same identity and the same events in every later snapshot and in the finished document. Failed 673 checks with the snapshot-based rule; passes with
the parser-based one.

## Decided later (2026-10-29)

- **No revision for the open block.** The open block changes whenever bytes arrive (its source grows), so a revision would only restate
  `document.source.count`, which a renderer already has. Not added.
- **No source range per block, yet.** What a renderer needs for selection and copy is where each drawn row came from, and the leaves give that (text runs,
  code lines and destinations name their bytes). A block range would serve "copy this block as written", including its markers (`>`, `-`, fences), which
  the leaves do not cover. It needs the parser to record each top-level block's first and last line, and care with a paragraph that turned out to be
  only reference definitions (removed from the tape, so its lines must not fall into the block before it). Built when a consumer asks for it; the first
  candidate is the TerminalKit renderer's copy (its roadmap 0022).
- **A walker can be reused** (`MarkdownEvents.restart(at:in:)`): a fresh walk allocates its two stacks, a restarted one nothing once warm (allocation
  suite).
