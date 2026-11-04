---
status: accepted
date: 2026-11-04
---

# 0003 — Top-level blocks know their bytes, and an edit restarts the parse and resynchronises with the old one

Extends ADR-0001 (two tapes) and ADR-0002 (stable identities). Ask roadmaps 0202, 0203 and 0205.

## Context

A viewer of a document that is edited in place (ask's transcript is not; a Markdown editor with a live preview, a Quick Look preview and a lab are) must draw only what an edit changed, and
must find it without parsing the document again or walking all of it. ADR-0002 deferred a block's source range "until a consumer asks"; three did (the viewer's copy, the editor's scroll sync, the diff).

## Decision

1. **A block index.** For each top-level block that closes, three slots on a tape of their own, committed with the block tape: its source range (from the first byte of its first line to the
   end of its last line with text, without that line's ending; an unclosed fence and an HTML block that nothing ended own the blank lines after their text), a wyhash of those bytes seeded
   with the block's kind, and its first slot. The hash also folds in, per leaf block that looked a reference up, what the label named (the destination and title as written, or that it named
   nothing), so a cache keyed by it cannot show a link that now means something else.
2. **Restart and resync.** An edit restarts a fresh parser at a line where nothing is open (after the end of the block above the one that holds the edit's line, and the one above that when the edit
   is on a block's first two lines), reads forward until its next top-level block starts at an offset where an old one did, shifted by the edit, and splices the region's tapes in place of the old
   blocks'. The tail moves once and its offsets and indices are shifted by one table lookup per slot (a container's `low` is a tape index, a leaf's an inline index, a range's a byte offset, a marker's
   a value). A link to a definition that stands before the edit does not move; one after it does, wherever the link is.
3. **The whole parse is the fallback and the oracle.** It is used when a definition (`]:`) came, went or moved in the region, when the document has a diagnostic, when the size limit applies, or
   when the restart would split a carriage return from its line feed. The tests compare the editor with a fresh parse of the edited source tape for tape.
4. **A formal model** (`docs/formal/EditResync.tla`) states that the blocks it gives are a fresh parse's, for every short document and edit over five kinds of line, and fails without the rule
   that the block above is read again (a table's delimiter row takes the line above it from a paragraph).

## Consequences

Parse cost rose about 11% in instructions (the index, the stamp), which the performance program (roadmap 0205) recovered in part (-3 to -10% from the SIMD cell scan, wyhash, labels). An edit costs the
region it reads plus the move of the tail; at the start of a 5 MB document 3.7 million instructions against 367 million, at the end 0.07 million. What a viewer keeps between edits is its own cache,
keyed by the content hash.
