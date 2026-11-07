# 0007: MarkdownLook draws a head as a panel of its properties

**Status:** accepted (2026-11-06). It replaces the GitHub-style table of ADR 0006's first amendment.

## Context

ADR 0006's first amendment drew a head as GitHub does: its keys across the top, its values in one row. Drawn on real heads (a
Jekyll post, a Hugo post, a JSON head, an Agent Skills file), that layout breaks down past a few short values. Long values wrap in
narrow columns, a nested mapping shows as JSON text, and the table runs past the page, so the native view lost its last columns.
Nothing marks it as the document's metadata either.

## Decision

A panel, as Obsidian's Properties and Notion's page properties show a page's metadata. One model, `FrontMatterPanel`, feeds the HTML
writer and the native builder:

- **Closed by default** to one line: the format (`YAML`, `TOML`, `JSON`), the `title` (or `name`), and the number of properties.
  It opens with a disclosure: HTML's `<details>`, which needs no script, and a tap in the native view. The Settings window's "Show
  a document's properties open" (`ViewerSettings.opensFrontMatter`) changes the default.
- **One row per key**, its key small and muted. The keys of a nested mapping, and the items of a list of mappings (numbered), are
  indented under their key. The rows are flattened with an explicit stack, without recursion.
- **Values by kind**: a list of scalars as tags; a flag as a check (true) or a dash (false); an RFC 3339 date or date-time in the
  reader's locale (an instant in their time zone, a local date as written); an absolute `http`, `https` or `mailto` address as a
  link (a relative one has nothing to be relative to in a preview); a null as nothing.
- **A card** in the page's own tokens (`--tint`, `--rule`, `--radius`), light and dark.
- A head that is not a mapping, or does not read without a diagnostic, is still shown as its lines, as code in its format.

## Verification

`FrontMatterTests` (MarkdownLookKit): the rows of a head with every kind of value, with a fixed locale and time zone; the closed
and the opened HTML, escaped and balanced; TOML and JSON heads; the code fallback; the native panel and what copying it gives; a
document without a head reading as before. 100 tests. Under a mutant that left nested keys unindented, two failed. The compare tool
drew both views of a Jekyll and a Hugo head, closed and open, light and dark, and they agree. The app builds with the new setting.

## Amendment (2026-11-06): long values and Jekyll's dates

Drawn on a Jekyll post, a Hugo post, an Agent Skills file and an Obsidian note, open and closed, light and dark, two things were
wrong. The native view cut a long value to one line: a grid row may be given one line's height, so values now wrap at their
column's width (`fixedSize(horizontal: false, vertical: true)`). A date as Jekyll writes it (`2026-03-14 09:30:00 +0100`, Ruby's
form) or as YAML 1.1 does (`2001-12-14 21:59:43.10 -5`) was shown as written; white space before an offset without its colon or
minutes now reads as RFC 3339 (`DateText.spacedOffset`). `FrontMatterTests.spacedDates`; a mutant that skipped the rewrite failed
three of its expectations.

## Amendment (2026-11-07): on the text's grid, without a box

The card read as a component on the page: a filled box with a stroke, a rule under its summary, an outlined capsule per tag, rows
with their own padding and a smaller size. The head now has no box, no rule and no outline. It sits on the body text's own grid,
so its spacing is the text's spacing.

- Every line is one leading of the text (1.6 em, `--leading`; `lineHeight(.exact(points:))` in the native view), at the text's
  size. Keys and values share a baseline. Above the head there is nothing; below it, the space between paragraphs (`.prose`), not
  a box's.
- Closed, the head is one line: the title, the format and the count, muted. The chevron hangs in the margin, as a list's marker
  does, so the title stands at the column's edge.
- Open, the head has a line per property. The key is muted at the column's edge, indented a level per nesting. The value starts
  in one column.
- A list of scalars is written as words: a muted middle dot between items, and no-break spaces inside an item ("Claude Opus 4.6"),
  so a line breaks between items only. A flag is written as `true` or `false`.
- A block scalar's last newline (`>` and `|` keep one) is not drawn as an empty line. Its other lines are kept.

`FrontMatterTests` was updated for the markup, and `blockScalars` is new (a mutant without the trim fails it). The compare tool
drew a Jekyll post, an Obsidian note and Copilot and Claude agent files, light and dark, and the two views agree.

## Amendment (2026-11-07, later): an outlined box, a column of properties, groups

Without a box the head did not read as one thing, and the two-column grid read as a table. It is now:

- An outlined box: a border of the page's stroke (`--stroke`, 1.5 px: a rule's, a quote's bar, a table's outline), in the rule's
  colour, with a code block's radius and padding (`--pad`, 1.1 em by 1.3 em) inside it, and the space of a box around it (`.box`).
- Closed, one line: the title (or nothing) and how many properties, the chevron at the line's end. The format (YAML, TOML, JSON) is
  not shown: the reader does not need it to read the properties.
- Open, one column: each property a dimmed key (secondary, 0.92 em) over its value, both on the text's leading (1.6 em), properties
  `--gap-s` apart. A null or an empty collection reads `none`, muted.
- A nested mapping, or a list with a mapping or list in it, is a group: its key opens and closes it (open to start), with the same
  chevron at its end, and its column is indented by `--indent` behind a bar of the stroke, as a quote's is. A list's items are
  keyed 1, 2, …. The panel's model is a tree (`Row.children`); groups deeper than `FrontMatterPanel.deepest` (24) are written as
  their JSON on one line, so neither view recurses without bound.
- In the native view each line is set as the page sets it (`BalancedLayout`, and the half-leading offset of `NativeMetrics`), and a
  group's chevron is at its key's size, so the baselines of a line agree. The compare tool drew a nested opencode-style agent,
  Copilot's orchestrator, a Jekyll post, a Hugo page and an Obsidian note, light and dark, open and closed: the box is the same
  height in both views (within 2 pt for five nested groups).

## Amendment (2026-11-07, code words): values a program reads are set in the code face

A head mixes prose (a title, a description) with words a program reads: a model's identifier, a mode, a tool's name, a path, a
number, a flag. The second kind is now set in the code face (the page's `code`, 0.9 em, without its tint), so the two read apart.

- A string is code when it has no white space, is at most 64 characters, and its key is not a prose property (`title`, `subtitle`,
  `description`, `summary`, `excerpt`, `caption`, `alt`): a one-word title is still a title. Numbers, flags and a group too deep to
  draw (its JSON) are code. Dates and links are not.
- A list of scalars is code when every item is; one item with a space ("Claude Opus 4.6") keeps the whole list prose. The dots
  between items stay in the text's face.
- On the page the code keeps the line's leading (`line-height: 1` inside the line, so the line box stays 1.6 em); in the native
  view it sits on the text's strut (`NativeMetrics.shift`), as an inline `code` does. `codeWords` tests the rule (a mutant without
  the prose keys fails it); the compare tool's boxes are the same height in both views.
