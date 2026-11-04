# Public Markdown corpus

The benchmarks and the corpus tests run on real, public documents. They are **not in the repository**: `manifest.json` lists each one (URL, size, SHA-256) and a setup step downloads them into a cache.

```sh
python3 Benchmarks/Corpus/fetch.py setup     # download what is missing, check every SHA-256
python3 Benchmarks/Corpus/fetch.py verify    # check the cache against the manifest
python3 Benchmarks/Corpus/fetch.py stats     # sizes
python3 Benchmarks/Corpus/fetch.py path      # where the cache is
```

- The cache is `~/Library/Caches/AemiMarkdownCorpus/files`; `AEMI_MARKDOWN_CORPUS` points elsewhere.
- Only public documents belong in the manifest (documentation sites that publish Markdown, public repositories). A private document never enters it.
- `discover` rebuilds the manifest from the sites' `llms.txt` indexes and public repository file lists. It is a maintainer step: it changes the manifest, which is reviewed like code.
- Tests that need the corpus (`CorpusIndexTests`) are disabled, with the reason, when the cache is empty. The benchmark: `cd Benchmarks/MarkdownBench && swift build -c release && .build/release/MarkdownBench --corpus --rounds 5`.
