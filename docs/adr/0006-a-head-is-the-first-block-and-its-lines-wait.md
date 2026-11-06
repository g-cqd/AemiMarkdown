# 0006: A head is the first block, and its lines wait until it is decided

**Status:** accepted (2026-11-06).

## Context

Markdown files often start with a head: `---` YAML (Jekyll, GitHub, the Agent Skills format), `+++` TOML or a leading JSON object
(Hugo). CommonMark has no such thing. Without an extension, `---` is a thematic break and `title: x` above a later `---` a setext
heading. The owner asked for heads as a block of their own (AemiHMMML's ADR-0009). Since no specification covers front matter,
AemiHMMML's `AemiFrontMatter` holds the rules, each taken from a tool's code (its ADR-0015). AemiMarkdown follows those rules and
writes no grammar of its own.

## Decision

1. **An extension, off by default.** `MarkdownExtensions.frontMatter` (bit 7; the option set widened to `UInt16` for the ones to
   come). It is not in `.github`: GitHub draws a head as a table, which is a renderer's choice. Off, nothing changes: the 682
   specification examples and every other test pass as before.
2. **One block.** The head is the first top-level block, a `NodeKind.frontMatter` container (payload 1 YAML, 2 TOML, 3 JSON)
   whose children are its content's lines as `codeLine` leaves, fences excluded. Its source range runs from the opening fence
   to the end of the closing fence's line. `MarkdownDocument.frontMatter` says where it is and in what format, and
   `readFrontMatter()` reads it with `ErrorPolicy.recovering`: a Markdown document never fails, so a broken head yields its
   diagnostics, with offsets in the document. The body is parsed as Markdown would parse it alone.
3. **Lines wait while the head is undecided.** From the first byte, complete lines are held back until `FrontMatterStream`
   decides. Once it does, they are either the head's or parsed as Markdown, in order. A snapshot taken meanwhile closes a copy,
   which decides as if the input had ended, so an open head is drawn provisionally as Markdown and becomes a head when its
   closing fence arrives. The stream resumes where it stopped, so the wait costs each byte a bounded number of looks. The
   `maxFrontMatterBytes` limit (64 KiB) bounds how long lines can wait: an opening `---` that nothing closes within it is Markdown.
4. **The body starts a line.** A JSON head with text after its `}` on the same line is no head here, because every block starts
   a line (ADR-0003's index relies on it).
5. **Edits near the head parse whole.** The editor's regions never re-read the start of a document. An edit that may open, close
   or change the head parses the whole document, and the change it reports is still exact (one block, for an edit inside the
   head). Such an edit is one before the body's start, within the bound past an opening fence that was not closed, or on the
   first line. Edits further on resync as before. Re-reading only the head is left for later.

## Consequences

- With the extension off, strict reading pays one comparison per line (`headBodyStart`, `Int.max` while a head is undecided), plus
  a parser larger by 16 bytes. On the 998-document corpus, instructions per byte rose 0.2 to 0.5 % per size bin (for example 63.9
  to 64.1 for 20–100 KB, 103.3 to 103.6 for the largest). A first draft kept the head's state inline and cost 1.2 %. The parser
  is still copied by its non-mutating helpers on this branch, so its size shows in those copies.
- Renderers draw nothing new yet: a `frontMatter` block falls to their `default` cases. Hiding it, or drawing a table as GitHub
  does, is theirs to choose.

## Verification

`FrontMatterTests`: the block and its lines; TOML and JSON heads; a broken head read with its diagnostics; for 15 texts, the body
equals the body parsed alone, and a text without a head reads exactly as with the extension off; the bound; streaming in pieces of
1, 2, 3 and 7 bytes with a snapshot after each (valid tapes, and the same tapes as a whole parse); every one-byte edit of every text
(delete, insert `x`, a line break, `---\n` or `-`) checked against a fresh parse by `EditOracle`, tape for tape; 400 random
documents from the fences' alphabet, streamed and edited. The release suite passes, allocation ceilings included.

## Amendment, 2026-11-06: MarkdownLook draws a head as GitHub does

MarkdownLook reads with `[.github, .frontMatter]` (`MarkdownLook.extensions`) in its preview, its app and its lab. Both renderers
draw a head from one model, `FrontMatterTable`: its keys as a header row and its values as one row. A scalar shows its text, a list
of scalars its items joined by commas, and anything deeper its compact JSON (AemiHMMML's projection, at the revision pinned here).
A head that is not a mapping, or does not read without a diagnostic, is shown as its lines, as code in its format. Copying the
native row gives the head as written. `FrontMatterTests` in MarkdownLookKit cover YAML, TOML and JSON heads, the code fallback, the
native table, and a document without a head reading as before. The table cases were seen to fail under a mutant that never builds
a table.

## Amendment, 2026-11-06: an edit inside the head re-reads only the head

An edit whose range lies inside the head's content reads a region from the start of the document. `beginRegion(at: 0)` starts the
head as a whole parse does. The region resynchronises at the first body block, moved by the edit, and the head block alone is
spliced. The region's head must end where the old one did, moved by the edit, and in the same format; then the body's bytes are
unchanged. Otherwise, and for any edit on a fence or that may open or close a head, the editor parses whole, as before. The
one-byte-edit oracle over the 15 texts runs through this path, and `headOnlyEdits` checks it is taken: one block out, one in,
`lastEditParsedWhole` false. Under a mutant that refuses every head edit, its three head-only cases failed.

