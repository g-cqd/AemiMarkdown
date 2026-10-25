#!/usr/bin/env python3
"""Reference HTML for a set of Markdown inputs, for the differential test (Tests/AemiMarkdownTests/DifferentialTests.swift).

  Scripts/reference-html.py core OUT.ndjson --random 5000 --seed 1
  Scripts/reference-html.py ext  OUT.ndjson --corpus corpus.ndjson

core: CMARK (default /tmp/cmark-up/build/src/cmark, cmark 0.31.2, the reference of CommonMark 0.31.2), no extensions.
ext:  CMARK_GFM (default /tmp/cmark-gfm-src/build/src/cmark-gfm) with tables, strikethrough and autolinks. cmark-gfm implements spec 0.29, so only
      inputs that use an extension are meaningful there; the differences that 0.29 and 0.31 have between them are not parser faults.

The corpus is NDJSON, one {"t": "..."} per line (never committed: it is made of private session logs). Each output line is {"t": input, "h": html}.
"""
import json, os, random, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

LINE_STARTS = ["", "", "", "- ", "* ", "+ ", "1. ", "2) ", "> ", "> > ", "# ", "## ", "    ", "  ", "\t", "- - ", "-\t", "- [ ] ", "```", "~~~", "```swift", "***", "---", "===", "___",
               "| ", "|", "[x]: /u", "[x]: /u \"t\"", "<div>", "</div>", "<!-- ", "-->", "<pre>", "1.", "-", "10. ", "   ", "      "]
INLINES = ["word", "foo", "bar baz", "*", "**", "_", "__", "`", "``", "[", "]", "](", ")", "![", "<a>", "</a>", "<http://a.b>", "<a@b.co>", "&amp;", "&#35;", "&bogus;", "\\", "\\*", "\\\\",
           "http://example.com/a_b", "www.example.com", "a@b.co", "~~", "~", "|", "---", ":--", "[x]", "[x][]", "[x][y]", "(u 't')", "(<u v>)", "é", "→", "  ", " ", "\t", "<!--c-->", "'", "\"", "#", "="]

def random_doc(rng):
    lines = []
    for _ in range(rng.randint(1, 9)):
        parts = [rng.choice(LINE_STARTS)] + [rng.choice(INLINES) for _ in range(rng.randint(0, 6))]
        sep = rng.choice(["", " ", " "])
        lines.append(sep.join(parts))
    return "\n".join(lines) + rng.choice(["\n", "\n", "\n\n", ""])

def run(binary, args, text):
    return subprocess.run([binary, "--unsafe", *args], input=text.encode(), capture_output=True, timeout=30).stdout.decode("utf-8", "replace")

def main():
    mode, out = sys.argv[1], sys.argv[2]
    options = dict(zip(sys.argv[3::2], sys.argv[4::2]))
    if mode == "core":
        binary, args = os.environ.get("CMARK", "/tmp/cmark-up/build/src/cmark"), []
    else:
        binary, args = os.environ.get("CMARK_GFM", "/tmp/cmark-gfm-src/build/src/cmark-gfm"), ["-e", "table", "-e", "strikethrough", "-e", "autolink"]
    if "--corpus" in options:
        texts = [json.loads(l)["t"] for l in open(options["--corpus"]) if l.strip()]
        limit = int(options.get("--limit", "0"))
        if limit: texts = texts[:limit]
    else:
        rng = random.Random(int(options.get("--seed", "1")))
        texts = [random_doc(rng) for _ in range(int(options.get("--random", "1000")))]
    with ThreadPoolExecutor(8) as pool:
        htmls = list(pool.map(lambda t: run(binary, args, t), texts))
    with open(out, "w") as f:
        for t, h in zip(texts, htmls):
            f.write(json.dumps({"t": t, "h": h}, ensure_ascii=False) + "\n")
    print(len(texts), "inputs ->", out)

main()
