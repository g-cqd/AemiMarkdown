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
| `python/` | cmarkgfm (cmark-gfm in C), mistune, Python-Markdown | |

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
