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

## Not decided

A source byte range per block (a renderer that copies Markdown source would want it; computing it walks the subtree), and a revision for the open
block (a renderer lays it out again on every snapshot today).
