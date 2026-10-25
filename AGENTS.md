# Working in AemiMarkdown

A Markdown parser for terminals and streams: UTF-8 bytes in, two flat tapes out, incremental, bounded, never failing. Read `docs/adr/0001-*.md` first.

- **Build and test in release**: `swift test -c release --enable-testable-imports`. A debug build measures a program nobody ships. `AEMIMARKDOWN_DEV=1` adds the AemiRegex
  differential tests.
- **The spec is the test.** `Tests/AemiMarkdownTests/Fixtures/` holds CommonMark 0.31.2 and the GFM extensions (CC BY-SA, see `LICENSE.md` there). The ratchet
  (`Fixtures/known-failing.txt`) shrinks and never gains an entry. `Scripts/update-ratchet.sh` rewrites it after a fix and refuses to add one.
- **No recursion, no failure.** Nesting is an explicit stack with a limit; any bytes give a document. A new loop needs its bound.
- **Zero allocation per node.** The parser reuses its buffers; a test counts allocations per input with Aemi's `CAemiTestKitMalloc`.
- **Measure.** Throughput, allocations per KB and the streamed-delta cost are compared with the swift-markdown baseline in ask's diary 2026-10-25-01. A change that
  can affect them is benchmarked before and after, median and spread, release build.
- **One Aemi revision** for the graph (`Package.swift`): ask, TerminalKit and AemiJSON pin the same one and move together.
- Style: `.swift-format` and `.swiftlint.yml` are Aemi's canonical files (`../aemi/scripts/sync-config.sh`); one primary type per file; files under 250 lines.
