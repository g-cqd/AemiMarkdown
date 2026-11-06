# MarkdownLook

A Quick Look preview and thumbnail for Markdown (`net.daringfireball.markdown`) and Mermaid (`.mmd`, `.mermaid`, type `studio.aemi.mermaid`) files, and a small viewer app that carries them.
The preview is an HTML reply made by `MarkdownLookKit` (ADR 0004): the document in the system font, light and dark, with `mermaid` fences drawn as inline SVG by AemiMermaid. Nothing in a
document runs: raw HTML is shown as text, links keep only http, https, mailto and relative destinations, images are not loaded, the reply has no script and needs no network.

```sh
swift test                      # the kit: structure, hostile input, tag balance, fuzz, the public corpus when set up
xcodegen generate               # MarkdownLook.xcodeproj (not committed)
xcodebuild -project MarkdownLook.xcodeproj -scheme MarkdownLook -configuration Release build
```

Signed ad hoc by default (`Signing.xcconfig`); set `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` there to sign for distribution (Developer ID and notarization are not done here). To try a build, copy
`MarkdownLook.app` to `~/Applications`, run `pluginkit -a` on both `.appex` files inside it, and `qlmanage -p file.md`.

Known limits: the system's own thumbnail wins for `.md` on the machine this was tried on (Mermaid thumbnails are drawn by the extension); selection in Quick Look's preview copies rendered text, not
Markdown source (the app's own view copies the Markdown of the rows it selects whole); edge labels in diagrams are stacked beside the edge rather than placed on it; the macOS 26 runtime has not been tried.

## The lab's source pane is coloured

The lab's left pane colours Markdown as it is typed (`MarkdownSourceHighlight`): markers dimmed, strong bold, emphasis slanted, headings bold and tinted at the size of the rest, code tinted, links and their targets, inline HTML. It is attributes only, so every character, the cursor, the selection and undo are as typed. What the bytes are comes from `MarkdownSourceHighlighter` in AemiMarkdown (the colouring ask's prompt has, made neutral); `AemiTextStyling` in `../../../AemiTextUI` applies it to the text storage over the window shown, so a keystroke in a long text re-colours a screenful. `Package.swift` therefore has a path dependency on the sibling checkout `AemiTextUI`.

## The native view and its harness

The app draws the document natively and holds it to the page (ADR 0005). To measure the difference, in release and off-screen:

```sh
swift build -c release --product markdown-look-compare
.build/release/markdown-look-compare FILE.md [--width 800] [--dark] [--blocks] [--columns --column-lines] \
    [--scroll-tables] [--outline] [--bleed] [--left] [--typeface serif] [--features ss01,tnum]
Scripts/compare-all.sh [--dark] [filter]    # the component fixtures, Fixtures/components/01 to 12
```

Pictures are written to `/tmp/ql/compare` (web, native, and the difference).

## A document's head is a panel of its properties

A head at the start of a document (`---` YAML, `+++` TOML, a leading JSON object) is drawn as a card closed to one line: its format,
its title and how many properties it holds (AemiMarkdown ADR 0007). Opened, it shows one row per key: nested keys indented, lists as
tags, flags as checks, dates in the reader's locale, web and mail addresses as links. Settings › Front matter opens it by default. A
head that is not a mapping, or does not read, is shown as code in its format. `Package.swift` depends on AemiHMMML and AemiJSON at
the revisions AemiMarkdown pins.
