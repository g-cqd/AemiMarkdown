# To read, then delete (left 2026-11-04 23:15 by the session that repinned swift-ci)

This checkout has diverged from origin/main; nothing of yours was pushed or changed.

- origin/main has one commit more than your base: `3292770 CI: swift-ci 27f96f0; the TLA+ models run as swift-ci's
  tla command …`, pushed from a separate clone so that your eight unpushed commits (6536fba … 56a4057, the editor,
  the benchmarks, EditResync and MarkdownLook) stayed local. It changes:
  - `.github/workflows/ci.yml`: the swift-ci pin.
  - `.ci/action.json`: the `tla-models` command is `"tla": { "models": "docs/formal" }` instead of
    `"run": "Scripts/tlc.sh"`. swift-ci checks every `.cfg` with the pinned TLC (1.7.4), each run in a state
    directory of its own, and every `.buggy.cfg` must be refuted, read from TLC's error line ("is violated", "is
    equal to FALSE", …), as your script did.
  - `Scripts/tlc.sh`: now `exec .ci/swift-ci run tla-models`, so the docs that name it still work.
- No file overlaps with your commits or your uncommitted MarkdownLook changes. Verified before the push: your six
  models (EditResync included) give the right verdicts through the new command, locally; on CI the four pushed
  ones did.
- What to do: `git pull --rebase --autostash` before you push. Report items 1, 2 and 7 are done this way; item 3
  is fixed in swift-ci (discipline counts only force unwraps), item 4 too (swift-ci recreates a dangling
  `.build` target), and item 5 stays with Apple (`SWIFT_BACKTRACE` set by swift-ci broke tests that read a
  child's stderr on macOS, so it was reverted).
- Then delete this file; it is not meant to be committed.
