# Fixtures

`commonmark-0.31.2.txt` is the CommonMark specification 0.31.2, by John MacFarlane, from
<https://github.com/commonmark/commonmark-spec> (tag 0.31.2). Its examples are the test cases.

`extensions.txt` is the GitHub Flavored Markdown extensions test file, by Yuki Izumi, from
<https://github.com/swiftlang/swift-cmark> (branch `gfm`, `test/extensions.txt`).

Both are licensed CC BY-SA 4.0 (<https://creativecommons.org/licenses/by-sa/4.0/>), as their headers say. They are
unchanged. They are test data, not part of the library: nothing in `Sources/` is derived from them, and the share-alike
terms apply to these files and to any adaptation of them, not to the rest of the repository (MIT).

`cmark-pathological_tests.py` is cmark's list of inputs that make a naive parser quadratic or exponential
(BSD-2-Clause, with cmark). It is read for the shapes of its inputs; `PathologicalTests.swift` builds its own.
