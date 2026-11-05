#!/usr/bin/env python3
"""Runs every engine of the comparison on the public corpus and prints one table (Benchmarks/Comparison/README.md says how to read it).

usage: run.py [--rounds N] [--python PATH] [--skip swift,rust,node,python] [--json results.jsonl]
Build first: see the README. The corpus is the cache `Benchmarks/Corpus/fetch.py setup` fills."""
import json, os, platform, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default
rounds = opt("--rounds", "5")
python = opt("--python", sys.executable)
skip = set((opt("--skip", "") or "").split(","))
corpus = os.environ.get("AEMI_MARKDOWN_CORPUS") or os.path.expanduser("~/Library/Caches/AemiMarkdownCorpus")
corpus = os.path.join(corpus, "files")
if not os.path.isdir(corpus) or not os.listdir(corpus):
    sys.exit("no corpus: run Benchmarks/Corpus/fetch.py setup")

runs = {
    "swift": [os.path.join(here, "swift/.build/release/CompareSwift"), corpus, "--rounds", rounds],
    "rust": [os.path.join(here, "rust/target/release/compare-rust"), corpus, "--rounds", rounds],
    "node": ["node", os.path.join(here, "node/bench.mjs"), corpus, "--rounds", rounds],
}
# Python engines are tens of times slower: one round, no warm-up, each alone with a time limit (`--limit` seconds, 600), and a table row that says so when it is not met.
for engine in ("cmark-gfm", "mistune", "python-markdown"):
    runs["python:" + engine] = [python, os.path.join(here, "python/bench.py"), corpus, "--rounds", "1", "--warmup", "0", "--engine", engine]
limit = int(opt("--limit", "600"))
timed_out = []
results = []
for name, command in runs.items():
    if name in skip or name.split(":")[0] in skip:
        continue
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=limit)
    except subprocess.TimeoutExpired:
        timed_out.append(name.split(":")[-1])
        continue
    if done.returncode != 0:
        print(f"{name}: failed\n{done.stderr[-400:]}", file=sys.stderr)
        continue
    results += [json.loads(line) for line in done.stdout.splitlines() if line.startswith("{")]

load = os.getloadavg()[0]
chip = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip()
results.sort(key=lambda r: -r["mbps"])
if (out := opt("--json")):
    with open(out, "w") as f:
        f.writelines(json.dumps(r) + "\n" for r in results)
first = results[0]
print(f"corpus: {first['documents']} documents, {first['bytes'] / 1e6:.1f} MB; {chip}; macOS {platform.mac_ver()[0]}; load average at the end {load:.1f}\n")
print("| Engine | Version | Does | MB/s | Relative to AemiMarkdown (HTML) |")
print("|---|---|---|---:|---:|")
base = next((r["mbps"] for r in results if r["engine"] == "aemimarkdown-html"), None)
for r in results:
    rel = f"{r['mbps'] / base:.2f}×" if base else ""
    print(f"| {r['engine']} | {r['version']} | {r['what']} | {r['mbps']:.1f} | {rel} |")
for name in timed_out:
    print(f"| {name} | | html | did not finish in {limit} s | |")
