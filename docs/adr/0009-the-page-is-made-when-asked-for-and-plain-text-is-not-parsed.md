# 0009: The page is made when it is asked for, and plain text is not parsed

**Status:** accepted (2026-11-14). Amends point 2 of [0008](0008-markdownlookkit-is-a-product-of-this-package-with-an-editor-saving-and-commands.md)
("the session replaces the same bytes and the page is made again").

## Context

Sunset measured what a document costs by its size before building its Markdown pane (its roadmap 0023 step M-b; release build,
its harness `OpenDocumentBenchTests`, Markdown as a person writes it: headings, paragraphs, lists, tables, code). The numbers are
Sunset's, taken on one machine while another build was running on it.

| | 20 KB | 200 KB | 2 MB | 10 MB |
| --- | --- | --- | --- | --- |
| Opening | 18 ms | 34 ms | 342 ms | 1,679 ms |
| A character typed (median) | 3.4 ms | 34 ms | 335 ms | 1,666 ms |
| Memory held once open | 2.4 MB | 8.6 MB | 83 MB | 377 MB |
| Saving (median) | 7 ms | 14 ms | 92 ms | 435 ms |

Where a typed character's time went at 2 MB: finding the edit's bytes 1.8 ms; the parser's `replace` 0.00 to 0.03 ms (it is
incremental, and never parsed the whole); **making the page again 336 ms**. So `MarkdownSource` paid for a page at every key
whether or not anything showed one, and an editor alone on a 200 KB file missed two frames a key.

Two more things showed:

- A text file that is not Markdown (a log of 200 KB, no blank line in it) is one paragraph to the parser: 125 ms a key, and it
  has no page to show.
- `isEdited` and `markSaved` hashed a `String` made from the text storage: 78 ms at 2 MB, most of what a save cost.

## Decision

1. **`MarkdownSource.document` is made when it is read**, and kept until the text or the settings change. It reads `revision`
   and `settings`, so whoever observes the page is still told of the next change. A source that only editors show makes no
   page. `pagesMade` counts them, for tests and measures.
2. **`MarkdownSource.Content`**: `.markdown`, `.diagram`, `.plain`. Plain text is held, edited, undone and compared with what
   was saved like any other, and the parser never sees it: `session` stays empty, `lastEdit` nil, `document` empty.
   `init(text:isDiagram:settings:)` stays, and `isDiagram` is now computed.
3. **The digest of the saved text** is taken over the storage's UTF-16 units in pieces: no `String` is made and no copy kept.
   It is stricter than before: two texts that are canonically equivalent and differ in their units now count as different,
   which is right for a file.

## Consequences

The same harness after, medians:

| | 20 KB | 200 KB | 2 MB | 10 MB |
| --- | --- | --- | --- | --- |
| Opening | 7 ms | 2 ms | 20 ms | 98 ms |
| A character typed, no page shown | 0.04 ms | 0.4 ms | 3.6 ms | 18 ms |
| A character typed, the page read after each | 3.5 ms | 33 ms | 327 ms | 1,640 ms |
| Memory held once open | 1.0 MB | 1.4 MB | 13.5 MB | 68 MB |
| Saving | 5 ms | 7 ms | 19 ms | 70 ms |

A plain log of 10 MB: opened in 17 ms, 10 MB held, a key 0.00 ms.

**Not solved, and said:** with the page shown, a key still costs the whole page (the third row): the rows are made from the
whole document each time. Making only the rows of the blocks the parser replaced (`LabEdit` already says which) is the next
step, and a host can meanwhile make the page less often than at each key. What a key costs without a page still grows with
the text (finding the edit's bytes is one pass up to it: 18 ms at 10 MB at the end of the text).
