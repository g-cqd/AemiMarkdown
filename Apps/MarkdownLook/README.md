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

Known limits: the system's own thumbnail wins for `.md` on the machine this was tried on (Mermaid thumbnails are drawn by the extension); selection in the preview copies rendered text, not
Markdown source; edge labels in diagrams are stacked beside the edge rather than placed on it; the macOS 26 runtime has not been tried.
