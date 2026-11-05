# Comparison with other Markdown engines

`Benchmarks/MarkdownBench` holds AemiMarkdown to its own numbers. This folder puts it beside other engines, on the same documents, doing the same job, so that the figure is not a claim about
one rival on one machine.

**The job** is *Markdown to HTML*, on one thread, because every engine has it. The corpus is the public one (`Benchmarks/Corpus`, 998 documents, 84.5 MB, downloaded and verified by its setup
step, never committed). Each engine converts every document, once to warm up and then for N rounds (five; the Python engines, which are far slower, one round with no warm-up); the figure is the best
round's **CPU time**, not wall time, so that other work on the machine does not count against it. Throughput is source megabytes over that time.

| Folder | Engines | Notes |
|---|---|---|
| `swift/` | AemiMarkdown, swift-markdown (cmark-gfm in C under a Swift tree), Foundation's `AttributedString(markdown:)` | AemiMarkdown is measured twice: building its tree (`-parse`, which is what the others' "tree" rows also do, and which is lazy over a tape) and writing HTML (`-html`, the viewer's writer with diagrams, highlighting and smart punctuation off) |
| `rust/` | pulldown-cmark, comrak | GFM tables, strikethrough, task lists and footnotes on |
| `node/` | markdown-it, marked, commonmark.js | CPU time of the process (it includes the garbage collector's threads) |
| `python/` | cmarkgfm (cmark-gfm in C), mistune, Python-Markdown | each alone, one round, with a time limit; Python-Markdown did not finish the corpus in nine minutes (under 0.15 MB/s) and is reported as that |

```sh
python3 Benchmarks/Corpus/fetch.py setup
(cd Benchmarks/Comparison/swift && swift build -c release)
(cd Benchmarks/Comparison/rust && cargo build --release)
(cd Benchmarks/Comparison/node && npm install)
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install cmarkgfm mistune markdown
Benchmarks/Comparison/run.py --python /tmp/venv/bin/python --json results.jsonl
```

## How to read it

- Engines do **not** produce the same HTML: they differ on raw HTML, on how much whitespace they keep, on extensions (autolinks, heading ids, syntax classes) and on escaping. Output bytes are in the
  JSON (`output_bytes`) so a large gap can be checked against a large difference in output. The conformance of AemiMarkdown is stated by its own suites (every CommonMark 0.31.2 and GFM example).
- The `tree` rows (AemiMarkdown, swift-markdown, Foundation) stop before HTML; they are shown to tell the cost of parsing from the cost of writing, and are not comparable with the `html` rows.
- One machine, one run, a corpus of documentation and READMEs (not chat messages, which are what `MarkdownBench`'s other table uses). A different corpus, chip or toolchain moves the figures; the
  ordering of engines more than the figures themselves is what to look at. Versions are in the output.
- This is a harness, not a verdict: no engine is tuned for it, each is called as its README calls it, and the pinned versions are the latest at the time of writing.

## A run (2026-11-05)

Apple M3, macOS 27.0.1, 998 documents (84.5 MB), best of five rounds of thread CPU time (Python: one round); the machine was shared and its load average was 4 to 9 during the run, so read ratios, not
decimals. Markdown to HTML unless the row says `tree`.

| Engine | Version | Does | MB/s |
|---|---|---|---:|
| pulldown-cmark (Rust) | 0.13 | html | 265.6 |
| AemiMarkdown, parse only | local | tree | 144.5 |
| comrak (Rust) | 0.40 | html | 85.5 |
| cmark-gfm (C, via cmarkgfm) | 2025.10.22 | html | 43.0 |
| **AemiMarkdown, viewer HTML writer** | local | html | 30.1 |
| commonmark.js | 0.31.2 | html | 22.0 |
| markdown-it | 14.3.3 | html | 21.6 |
| swift-markdown, parse only | ea1d88b | tree | 18.0 |
| marked | 16.4.2 | html | 11.9 |
| swift-markdown, HTMLFormatter | ea1d88b | html | 11.3 |
| Foundation `AttributedString(markdown:)` | system | tree | 3.6 |
| mistune | 3.4.0 | html | 2.2 |
| Python-Markdown | | html | did not finish in 9 minutes |

What it says: as HTML writers, AemiMarkdown (30 MB/s) is faster than the JavaScript engines, swift-markdown and the pure-Python ones, and **slower than the Rust engines and than cmark-gfm in C**. Its parse alone
(a tree, not comparable with the HTML rows) is the fastest Swift figure here. Its HTML writer is the viewer's: it escapes, drops controls, checks link schemes and marks up tables and footnotes. That is a finding, not a footnote: the writer is where the viewer's time goes, and the Rust
engines show what a lean one costs. The Python rows read the files with replacement characters, so their byte count is 50 bytes smaller than the others'.

## After the writer was rewritten (2026-11-05, later)

The profile of the first run said where the 30 MB/s went: a quarter of the time was copying the whole page so far for every table (`out = beforeTable + … + out`), and most of the rest was `String` appends, a `String` made for every text run, and a scalar-by-scalar escape. The writer now appends bytes to
one buffer, escapes straight from the source in one pass (smart punctuation in the same pass), rewrites a table in place, and keeps no strings for tag names. Its output is **byte for byte what it was** on all 998 documents, with the benchmark's settings and with the viewer's defaults (highlighting, smart punctuation, diagrams): `CompareSwift DIR --dump OUT`
before and after, `diff -r`. A property test (8,000 random byte strings, ill-formed UTF-8 included) holds the new escaper to the old `String` one.

| Engine | Does | MB/s |
|---|---|---:|
| **AemiMarkdown, viewer HTML writer** (parse and write, `String` out) | html | 90 to 115 |
| AemiMarkdown, same, as bytes (`bodyBytes`) | html | 100 to 115 |
| AemiMarkdown, the writer alone (documents parsed outside the timing) | write | about 190 |
| AemiMarkdown, parse only | tree | 140 to 195 |

Read it as a range: the machine was shared (load average 5 to 20), and the same binary gave 60 to 114 MB/s from one run to the next. The ordering against the rows above is what holds: the writer is about three times faster than it was, and AemiMarkdown as an HTML engine is now ahead of comrak (85) and cmark-gfm (43), and still well behind pulldown-cmark (266).
The parse and the write are now about equal halves of the time, so the next factor has to come from both: the profile of the writer is flat (the scan 11%, event decoding 11%, appends and uniqueness checks 14%), and the parse's own profile starts with `matchOpenBlocks` (6%) and the SIMD search (6%).
