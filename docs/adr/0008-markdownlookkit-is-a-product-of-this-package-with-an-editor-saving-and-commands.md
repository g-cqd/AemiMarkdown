# 0008: MarkdownLookKit is a product of this package, with an editor, saving and commands

**Status:** accepted (2026-11-13, by the owner, as step M-a of Sunset's roadmap 0023; his words on the editor: "make it a way better
architecture and sure make all of that public").

## Context

Sunset's Markdown pane (its refinement R6) shows a document rendered by the kit's native view, or as source in an editor, and any
number of panes can show one document. The kit was a target of the sub-package `Apps/MarkdownLook`, which SwiftPM cannot pin by
revision from another repository. Its editor was in the app (`SourceEditor`), tied to the lab's model, holding its own text. There
was no saving and there were no formatting commands.

## Decision

1. **A product of the root package.** `MarkdownLookKit` is declared in the root `Package.swift`; its sources stay in
   `Apps/MarkdownLook/Sources/MarkdownLookKit`. It is AppKit and SwiftUI for macOS 26 and later, while the parser goes back to
   macOS 15 and builds on Linux, so:
   - the target, its product and what it alone depends on (AemiMermaid, AemiJSON, AemiTextUI) exist only when the manifest is read
     on a Mac (`#if os(macOS)`): a Linux build has none of them;
   - every top-level declaration of the kit is `@available(macOS 26.0, *)`.
   The sub-package keeps the tools (`markdown-look-html`, `markdown-look-compare`) and the kit's tests, and links the kit from the
   root; so does the app's `project.yml`.
2. **One text behind every view: `MarkdownSource`.** It owns the text storage, the undo manager, the parser's session and the page.
   It is the storage's delegate, so every change of the characters is followed wherever it comes from (a key in any editor, a
   command, undo): the session replaces the same bytes and the page is made again. Colouring (attributes only) is not an edit.
   `isEdited` compares the text with what was last loaded or saved, by length and then by a digest, so undoing back to the saved
   text is not edited and no second copy of the text is kept.
3. **`MarkdownSourceEditor`** shows a source: a text view with its own layout on the source's storage, the source's undo manager
   through its delegate. It holds no text. Two editors of one source show the same text and share one history. It colours only the
   window of the storage it shows, so editors of one text do not undo each other's colours. `MarkdownEditorProxy` is the handle for
   what acts on an editor from outside (its selection, commands, the keyboard).
4. **`AtomicFile.write`**: a temporary file beside the destination, forced to the disk (`F_FULLFSYNC`, else `fsync`), renamed over
   it, then the folder synced. The old file's permissions are kept; a symbolic link is written through. A failure leaves the old
   file and no temporary file, and says which step failed with the system's error number.
5. **`MarkdownCommand`**: formatting as functions of the text and the selection that give a `MarkdownEdit` (UTF-16 offsets, as a
   text view counts). Each toggles. `MarkdownSource.perform` applies one as a single step of undo. Keys are the host's (Sunset asks
   for them at its step M-g).

## Consequences

- A package that depends on AemiMarkdown on a Mac now resolves AemiMermaid, AemiJSON and AemiTextUI too (fetched, not built unless
  the kit is used). Accepted by the owner.
- The kit's sources are outside `Sources/`, so swift-ci's analyzers do not read them, as before.
- `LabSession.utf8Offset(ofUTF16:)` walks the bytes instead of making a string of the whole text for each call.

## Verification

`AtomicFileTests` (4), `MarkdownCommandTests` (8), `MarkdownSourceTests` (6) in `Apps/MarkdownLook/Tests`; the kit's 105 earlier tests
pass unchanged (123 in all). The root package builds; the app builds from `project.yml` with XcodeGen. Not seen: the editor on
screen (the lab uses it), typing coalesced into undo steps by AppKit, the cost of an edit on a long document (Sunset's step M-c
measures it).
