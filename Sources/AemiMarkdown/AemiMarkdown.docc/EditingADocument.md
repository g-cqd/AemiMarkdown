# Editing a document

Replace bytes anywhere and learn which blocks differ, in time that follows the edit and not the document.

## Overview

``MarkdownEditor`` holds a finished document. ``MarkdownEditor/replace(_:with:)`` puts bytes in place of a range of the source, wherever it is, and returns a ``MarkdownChange``: the
first block that differs, how many old blocks became how many new ones, and how far the bytes and the blocks after it moved. A viewer draws again only
``MarkdownChange/changedBlocks`` and keeps every other block's rows; a caret or a scroll position maps through ``MarkdownChange/newOrdinal(ofOld:)`` and
``MarkdownChange/newOffset(ofOld:)``.

```swift
var editor = MarkdownEditor(Array("# Title\n\nfirst\n\nsecond\n".utf8))
let change = editor.replace(16 ..< 22, with: Array("2nd".utf8))
for ordinal in change.changedBlocks {
    let block = editor.document.block(at: ordinal)   // draw this one again
    _ = block
}
```

A block is named by what it is: ``MarkdownBlock/contentHash`` is a hash of its bytes, seeded with its kind, that also says what its reference links resolved to, so a renderer's
cache keyed by it hits for a block that moved and misses for a block whose link now means something else. ``MarkdownBlock/sourceRange`` is where its bytes are in
``MarkdownDocument/source`` (from the first byte of its first line to the end of its last line with text, trailing blank lines left out, except for a fence or an HTML block that nothing closed,
whose blank lines are its own), and ``MarkdownBlock/ordinal`` its place in the list. ``MarkdownDocument/blocks(from:)`` starts a walk at an ordinal.

### How an edit is done

The parse restarts at a line where nothing is open, a block or two before the edit (the block above when the edit is on a block's first two lines, since a table's delimiter row takes a
line from the paragraph above it), reads forward until a top-level block of the new text starts where one of the old text did, and splices what it read into the tapes. An edit costs the
region it reads plus the move of everything after it: at the start of a 5 MB document 3.7 million instructions, against 367 million for parsing it whole, and at the end 0.07 million.
It parses the whole instead when a link reference definition came, went or moved in the region it reads, when the document has a diagnostic, or when the new source would pass
``MarkdownLimits/maxDocumentBytes``: the answer is the same, the cost is a parse. A test holds the editor to a fresh parse of the edited source, tape for tape, for every specification
example at every position and for random edits.

### Reading a code block

``MarkdownFenceReader`` gives a code block's style, info string, language and lines as byte ranges, and for a top-level block whether a closing fence ended it. A reader kept from one block
to the next allocates nothing.

```swift
var reader = MarkdownFenceReader()
for block in editor.document.topLevelBlocks {
    guard let header = reader.read(block, in: editor.document), header.isClosed == true else { continue }
    _ = (header.language, reader.lines)
}
```
