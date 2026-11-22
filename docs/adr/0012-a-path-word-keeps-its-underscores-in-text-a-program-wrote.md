# 0012: A path word keeps its underscores, in text a program wrote

**Status:** accepted (2026-11-22).

## Context

ask draws a model's replies with AemiMarkdown, and models write paths without backticks. On macOS the temporary folder is
`/var/folders/_l/…/T/`, so a reply naming `/var/folders/_l/mtv6_00gn/T/tmpx_/notes.txt` holds `_l/…/tmpx_`: an underscore after `/`
opens emphasis and one before `/` closes it (CommonMark 6.2), so the reply showed the path without its underscores, in italics, and
ask's link to it named no file. ask's PTY probe `probe-openers` failed on it one run in eight (ask's diary 2026-11-22-04). Globs do the
same with stars: `/tmp/*.png and /var/*.log` is emphasis. CommonMark is right about prose; a path is not prose.

## Decision

1. **An extension, off by default.** `MarkdownExtensions.pathWords` (bit 8). Not in `.github`, since GitHub does not do it. Off,
   nothing changes: every specification example and test reads as before.
2. **A path word.** A word is what lies between blanks (space, tab, line feed, carriage return). After any of `"'([<=` that open it,
   it is a path when it starts with `/` or `~/`, as ask's path links find one. A relative path (`a/_b_/c`) stays prose: too many
   prose words hold a slash.
3. **Its delimiters are text.** A run of `*`, `_` or `~` inside a path word is literal: it neither opens nor closes emphasis or
   strikethrough. Emphasis around a path (`*/usr/local*`) still reads, since that word starts with `*`. Code spans, links and
   autolinks are untouched.
4. **Read once.** The parser keeps the last word it read, so a word with many delimiters costs one pass: a 100 KB word with 50,000
   underscores takes 2 ms, and 2 s when read again for each (the test fails over 500 ms).

## Consequences

A path a model wrote reads as written and can be linked. Text that means emphasis right after a path-like word without a blank
(`/x/_y_`) loses it, which is the point. The check runs only on delimiter runs, and only when the extension is on.
