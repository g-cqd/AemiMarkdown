"""The Python engines of the comparison (Benchmarks/Comparison): cmarkgfm (cmark-gfm in C), mistune and Python-Markdown, Markdown to HTML, the best round's thread CPU time.
usage: bench.py DIR [--rounds N] [--engine NAME]"""
import json, os, sys, time
from importlib.metadata import version

args = sys.argv[1:]
def opt(name):
    return args[args.index(name) + 1] if name in args else None
directory = args[0]
rounds = int(opt("--rounds") or 5)
only = opt("--engine")
warmup = int(opt("--warmup") or 1)
docs = [open(os.path.join(directory, n), encoding="utf-8", errors="replace").read() for n in sorted(os.listdir(directory))]
total = sum(len(d.encode()) for d in docs)

def measure(name, package, convert):
    if only and only != name:
        return
    out = sum(len(convert(d)) for d in docs) if warmup else 0
    best = float("inf")
    for _ in range(rounds):
        start = time.thread_time()
        produced = sum(len(convert(d)) for d in docs)
        best = min(best, time.thread_time() - start)
        out = produced
    print(json.dumps({"engine": name, "version": version(package), "what": "html", "documents": len(docs), "bytes": total, "seconds": best, "mbps": total / best / 1e6, "output_bytes": out}), flush=True)

import cmarkgfm, cmarkgfm.cmark
measure("cmark-gfm", "cmarkgfm", lambda d: cmarkgfm.github_flavored_markdown_to_html(d))
import mistune
md = mistune.create_markdown(plugins=["table", "strikethrough", "footnotes", "task_lists"])
measure("mistune", "mistune", md)
import markdown
measure("python-markdown", "Markdown", lambda d: markdown.markdown(d, extensions=["tables", "footnotes", "fenced_code"]))
