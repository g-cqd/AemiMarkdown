# 0005: The native view matches the page, and a harness measures it

**Status:** accepted (2026-11-05).

## Context

The app draws a document natively (SwiftUI, no web view) while Quick Look answers with HTML (ADR 0004). A reader who moves from one to the other should not see two designs. The page's style
sheet is therefore the oracle: every measure of the native view is the page's, in the same em, and the difference is measured, not judged by eye.

## Decision

1. **One scale of space.** Rows carry their gap in em of the body text (`NativeRow.gap`), decided by the same sibling rules as the style sheet; container guides are one indent wide.
2. **Line boxes are exact.** A text block is a whole number of lines of the page's line height, with the half leading above the glyphs (`NativeMetrics`), headings balanced as `text-wrap: balance`
   does (`BalancedLayout`, CoreText, linear). Inline code, links and footnote marks are drawn by a `TextRenderer` (`PageTextRenderer`), not approximated by attributes.
3. **Tables are sized by the page's measures.** `TableLayout` (shared with the HTML writer) decides which columns keep their text on a line and whether the table is wide; `NativeTableGrid` shares
   the room as the browser's automatic layout does. A table scrolls without a scroll bar and without bounce; a setting lets it start at the text's edge and scroll across the window.
4. **Diagrams and pies are drawn from the scene's geometry** with text on baselines and the page's colours.
5. **Fonts are a setting per style** (text, headings, code, diagrams) with OpenType features; the style sheet and the native view read the same `ViewerFonts`.
6. **Selection is the document's.** Rows are separate views, so a selection is a pair of places (row, UTF-16 offset) kept by `DocumentSelection`, drawn behind the text from the layout's geometry, and
   copies the Markdown of the rows it covers whole.
7. **The harness** (`markdown-look-compare`) renders a file through the page in an off-screen web view and through the native column at one width, scale and appearance, and prints the similarity
   and the offsets of every band of ink in points; `--blocks` prints the page's boxes, `--columns` the column rules of each table in both. `Scripts/compare-all.sh` runs the component fixtures.
   It runs in release and never touches the screen's windows.

## Consequences

Measured at 800 pt (light), exact/blurred similarity: paragraph 71/82, headings 67/74, inline 72/83, code 93/96, quote 72/81, alert 71/82, lists 69/81, tasks 74/84, table 45/68, mixed 83/88,
diagram 94/97. Glyph antialiasing caps an exact score at 80 to 90 %; geometry is the measure that counts, and it agrees within 1 pt in the cases measured (text rows, table columns, outline).
Not matched: the table header's glyph weight, 0.5 pt of drift per heading row, Gantt and mind-map diagrams, and the selection's copy of rendered text where a row is selected in part.
