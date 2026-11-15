# 0010: A lone image is a row read from a local file, and the links that leave the page go to the host

**Status:** accepted (2026-11-14, for Sunset's roadmap 0023 step M-c; its refinement R6: "Images: local files only", "Links:
everything in a new split", "any text file as source").

## Context

The native view named an image and loaded none, opened web links in the browser itself and dropped the others, and the source
editor coloured every text as Markdown. A host that shows documents in panes (Sunset) needs pictures from the document's
folder, the links for itself, and plain text left alone.

## Decision

1. **`NativeContent.image(NativeImage)`.** A paragraph that is one image and nothing else (it may be inside a link) is a row of
   its own, with the paragraph's text kept as `fallback`. An image among words is named, as before.
2. **Local files only.** `NativeImage.file(base:)` gives a file of this Mac or nil: a path relative to the document's folder,
   an absolute path, or a `file:` address with no host; its query and fragment are dropped. Any other scheme, `//host/…` and
   `data:` are nil, so nothing is ever fetched. With no file, or one that does not read, the row draws its fallback: what a
   reader saw before this change.
3. **`NativeImageLoader`** reads the file off the caller's actor with ImageIO, decoded no larger than 2,560 pixels on its long
   side, and not at all when the file is over 64 MiB or is not a regular file. The size on the page is the picture's own at the
   density its file names, never wider than the column. Nothing is cached: a row that scrolls away lets its picture go.
4. **`NativeDocumentView(document:settings:base:onLink:)`.** `base` is the document's folder. With `onLink`, every link that
   leaves the page is the host's: a web or mail address as written, a relative link as the file it names. Without it, as
   before. `NativeLinkRoute` is that decision as a value, so it is tested without a view.
5. **`MarkdownSourceHighlight.apply(to:font:visible:)` on a `MarkdownSource`** colours Markdown as Markdown, and a diagram or
   plain text in one colour. The editor calls it.

6. **`MarkdownEditorProxy.isFocused`**: the editor's text view says when it takes and gives up the keyboard, so a host with
   several panes knows which was clicked.

## Consequences

- A document can make the app decode any picture file the app can read, in the app's own process, as Quick Look's previews do
  in theirs. The bounds above are what is done about it; decoding in a separate process is not.
- SVG is not read (ImageIO does not), nor an image among words, nor a picture's title.
- A link to a place in the same page (`#part`) still does nothing: the page has no named places.
- The row's height is known when the picture is read, so the page below it moves once.
- MarkdownLook's own windows pass no `base` yet and show pictures with an absolute path only.

Verified by tests (the row, the file rule, the loader's bounds, the route of a link, the colour of plain text, the
editor's focus). Seen once, drawn by
Sunset in a window that is not on screen (its `DocumentPaneCatalogTests`): a page with a picture from the document's folder.
Not seen in MarkdownLook itself.
