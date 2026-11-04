#!/usr/bin/env python3
"""The public Markdown corpus of AemiMarkdown's benchmarks and differential tests (ask roadmap 0205, 0203).

Only public documents: no private content ever enters the corpus. The documents are not stored in this repository (their authors own them); `manifest.json`
lists where each one came from, how big it was and its SHA-256 when it was fetched, and this script fetches them into a cache directory outside the repository.

    fetch.py setup               the setup phase: download exactly the documents manifest.json lists into the cache, check each against its SHA-256 and report the ones that changed upstream
    fetch.py verify              check the cache against manifest.json without downloading (a changed document is reported, never silently replaced)
    fetch.py stats               size distribution of the cache
    fetch.py path                print the cache directory (AEMI_MARKDOWN_CORPUS overrides it)
    fetch.py discover [--limit N]  a maintainer's command: build the candidate list from the sites' own indexes (llms.txt) and a list of public repositories' files, download them and rewrite manifest.json

The cache is the corpus: a benchmark reads the files in it, so two runs on one machine see the same bytes, and a machine that has run `setup` has the same documents as the manifest says (or is told which differ).
Tests and benchmarks that need the corpus say so and skip with the reason when the cache is empty; they never fail on, or silently pass without, a corpus.
"""
import concurrent.futures, hashlib, json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "manifest.json")
CACHE = os.environ.get("AEMI_MARKDOWN_CORPUS") or os.path.expanduser("~/Library/Caches/AemiMarkdownCorpus")
AGENT = "AemiMarkdown-corpus/1 (benchmark corpus; contact via the repository)"

# Sites that publish Markdown by appending .md and an llms.txt index of their pages.
INDEXES = [
    ("claude-code-docs", "https://code.claude.com/docs/llms.txt"),
    ("claude-platform-docs", "https://platform.claude.com/llms.txt"),
    ("codex-docs", "https://learn.chatgpt.com/docs/llms.txt"),
    ("cloudflare-docs", "https://developers.cloudflare.com/llms.txt"),
]
# Public repositories' files: long-tailed changelogs, READMEs, proposals, a book's chapters (raw files on the default branch).
REPOS = {
    "swiftlang/swift": ["CHANGELOG.md", "README.md", "docs/Lexicon.md", "docs/SIL/SIL.md"],
    "swiftlang/swift-package-manager": ["CHANGELOG.md", "README.md"],
    "swiftlang/swift-evolution": ["proposals/0306-actors.md", "proposals/0302-concurrent-value-and-concurrent-closures.md", "proposals/0296-async-await.md",
                                  "proposals/0338-clarify-execution-non-actor-async.md", "proposals/0414-region-based-isolation.md", "proposals/0458-strict-memory-safety.md"],
    "apple/swift-nio": ["README.md", "CONTRIBUTING.md"],
    "apple/swift-collections": ["README.md", "CHANGELOG.md"],
    "apple/swift-algorithms": ["README.md", "CHANGELOG.md"],
    "apple/swift-argument-parser": ["README.md", "CHANGELOG.md"],
    "rust-lang/rust": ["RELEASES.md", "README.md", "CONTRIBUTING.md"],
    "rust-lang/cargo": ["CHANGELOG.md", "README.md"],
    "rust-lang/book": ["src/ch04-01-what-is-ownership.md", "src/ch10-03-lifetime-syntax.md", "src/ch16-01-threads.md", "src/ch17-01-futures-and-syntax.md"],
    "nodejs/node": ["CHANGELOG.md", "README.md", "BUILDING.md", "doc/contributing/pull-requests.md"],
    "facebook/react": ["CHANGELOG.md", "README.md"],
    "vuejs/core": ["CHANGELOG.md", "README.md"],
    "microsoft/TypeScript": ["README.md", "CONTRIBUTING.md"],
    "golang/go": ["README.md", "CONTRIBUTING.md"],
    "python/cpython": ["README.rst"],
    "denoland/deno": ["README.md", "CONTRIBUTING.md"],
    "kubernetes/kubernetes": ["README.md", "CHANGELOG/CHANGELOG-1.30.md"],
    "git/git": ["README.md"],
    "github/gitignore": ["README.md"],
    "commonmark/commonmark-spec": ["README.md"],
    "github/docs": ["README.md", "CONTRIBUTING.md"],
    "cloudflare/workers-sdk": ["README.md", "CONTRIBUTING.md"],
    "openai/codex": ["README.md", "docs/config.md", "docs/getting-started.md", "CHANGELOG.md"],
    "anthropics/claude-code": ["README.md", "CHANGELOG.md"],
}
CF_PRODUCTS = 40          # Cloudflare publishes an llms.txt per product; use this many products
PAGES_PER_SITE = 260      # per documentation site, spread across its sections


def get(url, timeout=40):
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(), r.headers.get("content-type", "")


def candidates():
    found = []   # (source, url)
    for source, index in INDEXES:
        try:
            text = get(index)[0].decode("utf8", "replace")
        except Exception as e:
            print(f"index {index}: {e}", file=sys.stderr); continue
        urls = list(dict.fromkeys(re.findall(r"https://[^\s)>\]\"']+", text)))
        if source == "cloudflare-docs":
            products = [u for u in urls if u.endswith("/llms.txt") and u != index][:CF_PRODUCTS]
            pages = []
            for product in products:
                try:
                    sub = get(product)[0].decode("utf8", "replace")
                except Exception as e:
                    print(f"index {product}: {e}", file=sys.stderr); continue
                pages += [u for u in dict.fromkeys(re.findall(r"https://[^\s)>\]\"']+", sub)) if u.endswith(".md")]
            urls = pages
        else:
            urls = [u.rstrip(".,;:") for u in urls if u.rstrip(".,;:").endswith(".md")]
        step = max(1, len(urls) // PAGES_PER_SITE)
        found += [(source, u) for u in urls[::step][:PAGES_PER_SITE]]
        # the full-text concatenations some sites publish: very large single documents
        found += [(source + "-full", u) for u in re.findall(r"https://[^\s)>\]\"']+llms-full\.txt", text)[:1]]
    for repo, paths in REPOS.items():
        for path in paths:
            found.append((repo, f"https://raw.githubusercontent.com/{repo}/HEAD/{path}"))
    return list(dict.fromkeys(found))


def cache_path(url):
    return os.path.join(CACHE, "files", hashlib.sha256(url.encode()).hexdigest()[:24] + ".md")


def fetch_one(item):
    source, url = item
    path = cache_path(url)
    if os.path.exists(path):
        data = open(path, "rb").read(); return source, url, data, "cached"
    for attempt in range(3):
        try:
            data, kind = get(url)
            if len(data) == 0 or data.lstrip()[:1] == b"<" and b"<html" in data[:400].lower():
                return source, url, None, "not markdown"
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)
            time.sleep(0.05)
            return source, url, data, "fetched"
        except Exception as e:
            err = str(e)
            time.sleep(1 + attempt)
    return source, url, None, err


def cmd_discover(args):
    refresh = "--refresh" in args
    limit = int(args[args.index("--limit") + 1]) if "--limit" in args else None
    items = candidates()
    if limit: items = items[:limit]
    print(f"{len(items)} candidates; cache {CACHE}")
    if refresh and os.path.isdir(os.path.join(CACHE, "files")):
        for f in os.listdir(os.path.join(CACHE, "files")): os.remove(os.path.join(CACHE, "files", f))
    entries, failures, n = [], [], 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for source, url, data, status in pool.map(fetch_one, items):
            n += 1
            if data is None: failures.append((url, status)); continue
            entries.append({"source": source, "url": url, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
            if n % 100 == 0: print(f"  {n}/{len(items)}")
    entries.sort(key=lambda e: (e["source"], e["url"]))
    json.dump({"note": "Public documents, fetched for local benchmarking and not redistributed; their authors own them. Re-fetch with fetch.py; a changed hash means the document changed upstream.",
               "documents": entries}, open(MANIFEST, "w"), indent=1)
    print(f"{len(entries)} documents, {sum(e['bytes'] for e in entries)/1e6:.1f} MB; {len(failures)} failed")
    for url, why in failures[:15]: print("  failed:", url, why[:80])


def cmd_setup(_):
    entries = load_manifest()
    items = [(e["source"], e["url"]) for e in entries]
    expected = {e["url"]: e["sha256"] for e in entries}
    print(f"{len(items)} documents in the manifest; cache {CACHE}")
    fetched = cached = changed = 0; failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for source, url, data, status in pool.map(fetch_one, items):
            if data is None: failures.append((url, status)); continue
            fetched += status == "fetched"; cached += status == "cached"
            if hashlib.sha256(data).hexdigest() != expected[url]: changed += 1; print("changed upstream since the manifest was written:", url)
    print(f"{fetched} downloaded, {cached} already cached, {changed} differ from the manifest, {len(failures)} unavailable")
    for url, why in failures[:15]: print("  unavailable:", url, why[:80])
    sys.exit(1 if failures and len(failures) > len(items) // 10 else 0)


def load_manifest():
    return json.load(open(MANIFEST))["documents"]


def cmd_verify(_):
    bad = missing = 0
    for e in load_manifest():
        path = cache_path(e["url"])
        if not os.path.exists(path): missing += 1; continue
        if hashlib.sha256(open(path, "rb").read()).hexdigest() != e["sha256"]: bad += 1; print("changed:", e["url"])
    print(f"{len(load_manifest())} documents in the manifest; {missing} missing from the cache; {bad} differ from the manifest")


def cmd_stats(_):
    sizes = sorted(os.path.getsize(os.path.join(CACHE, "files", f)) for f in os.listdir(os.path.join(CACHE, "files")))
    pct = lambda q: sizes[min(len(sizes) - 1, int(len(sizes) * q))]
    print(f"{len(sizes)} files, {sum(sizes)/1e6:.1f} MB; p10 {pct(.1)} p50 {pct(.5)} p90 {pct(.9)} p99 {pct(.99)} max {sizes[-1]}")
    for lo, hi in [(0, 500), (500, 1000), (1000, 2000), (2000, 5000), (5000, 10000), (10000, 20000), (20000, 50000), (50000, 100000), (100000, 400000), (400000, 10**12)]:
        c = sum(1 for s in sizes if lo <= s < hi); print(f"  {lo:>7} .. {'inf' if hi > 10**11 else hi:>7}: {c:5d} {100*c/len(sizes):5.1f}%")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "stats"
    {"setup": cmd_setup, "discover": cmd_discover, "verify": cmd_verify, "stats": cmd_stats, "path": lambda _: print(CACHE)}[cmd](sys.argv[2:])
