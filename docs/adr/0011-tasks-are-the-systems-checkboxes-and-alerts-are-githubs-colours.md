# 0011: A task's box is the system's checkbox, and an alert has GitHub's colour and icon

**Status:** accepted (2026-11-17, Sunset's owner: "checkboxes are not rendered (they should render the default macos
checkboxes)", alerts "don't render different colors and don't support varying case").

## Context

The native view drew a grey box of its own for a task and could not act on it: the parser kept no place for the `[ ]`. Every
alert had the same grey bar and an upper-case grey title. The type of an alert was already read in any case (`[!note]`,
`[!NoTe]`), by a test added on 2026-11-17 that passed when written; the report came from the alerts looking alike.

## Decision

- A `taskMarker` is a `range` slot of the inline tape: its three bytes in the source, so an edit before it moves it as it moves
  text. The slot's payload is the length plus whether it is checked (3 or 4); `MarkdownNode` gives back `range` (three bytes)
  and `payload` (0 or 1) as before. The source highlighter dims it as a marker.
- `NativeMarker.task(done:at:)` keeps where the `[` is. The view draws `Toggle(.checkbox)`, the control size nearest the text
  (small below 11 points, large from 17). A click calls the action set by `onTaskToggle(_:)` with that offset;
  `NativeMarker.toggle(in:at:)` says what to write (`[ ]` ⇄ `[x]`) or nil when the bytes are no longer a box. With no action the
  box is shown and does not take clicks.
- An alert's bar, icon and title take its colour, GitHub's (Primer): note #0969da/#4493f8, tip #1a7f37/#3fb950, important
  #8250df/#ab7df8, warning #9a6700/#d29922, caution #d1242f/#f85149 (light/dark). The title is written as GitHub's documentation
  writes it ("Note"), at the text's size, after the system symbol nearest GitHub's icon.
- The style sheet does the same for the page: `.alert.KIND` sets `--alert`; a checkbox is the system's (no `appearance: none`).

## Consequences

- The HTML keeps `disabled` on a checkbox (cmark-gfm's output), so WebKit draws it dimmed; the page has no icons before the
  titles. Neither is done.
- `> [!NOTE] With a title after` stays a plain quote, as on GitHub; a custom title (Obsidian's form) is not read.
