# 0004: The viewer writes HTML and trusts nothing in the document

**Status:** accepted (2026-11-04). Referred to in the code of `Apps/MarkdownLook` as "ADR 0007" (the number it has in the ask roadmap); the numbering here follows this repository.

## Context

MarkdownLook is a Quick Look preview and thumbnail for Markdown and Mermaid files. A Quick Look extension may answer with HTML, with a PDF, or with a view; the HTML reply gives selection, find, zoom,
the system font and light and dark appearance without a view of our own, and SVG inside it is vector. A previewed file is untrusted input, opened by a click in Finder.

## Decision

1. **`MarkdownLookKit` turns the event stream into HTML** in one pass, with the open elements on an explicit stack (no recursion). Mermaid fences become inline SVG from `AemiMermaidSVG`.
2. **Nothing the document says is markup.** Text and attribute values are escaped, with controls and bidirectional controls dropped; raw HTML is shown as text; a link keeps its destination only when
   the scheme is `http`, `https` or `mailto` (or there is none), read as a browser reads it; images are named and never loaded; no script is written, and the preview needs none. The reply also
   needs no network.
3. **Typography is one style sheet** of the system font at 13 px, a line of 1.4 and a measure of 42 em, with light and dark by `prefers-color-scheme`; smart punctuation is applied to prose only.
4. **Tests:** structure on spec-shaped examples, a tag-balance checker, mutation fuzzing, nesting depth, hostile links and labels, and every public corpus document as a page.

## Consequences

The selection copies rendered text, not the Markdown source (a native view would copy source; that is the SwiftUI view of roadmap 0199). A thumbnail is drawn by CoreGraphics from the same document.
