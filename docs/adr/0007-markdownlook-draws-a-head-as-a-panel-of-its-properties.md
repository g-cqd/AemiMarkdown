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
