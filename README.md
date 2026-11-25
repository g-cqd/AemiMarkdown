# AemiMarkdown

Streaming, bounded, zero-copy Markdown parser for Swift 6. Reads UTF-8 bytes into flat block and inline offset tapes supporting CommonMark 0.31.2 plus GitHub Flavored Markdown tables, task lists, strikethrough, autolinks, alerts, footnotes, and front matter.

```swift
import AemiMarkdown

let document = MarkdownParser.parse(Array(source.utf8))
for block in document.blocks {
    // Inspect block kinds and UTF-8 source ranges without copying text
}
```

## Requirements

- Swift 6.4+ (Swift 6 language mode)
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+, or Linux

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/AemiMarkdown.git", branch: "main")
]
```

## Products

| Product | Description |
| --- | --- |
| `AemiMarkdown` | Streaming and incremental UTF-8 tape parser, GFM extensions, source highlighting |
| `MarkdownLookKit` | Rendering helpers built on `AemiMarkdown` |

## Documentation

- [Formal Models](docs/formal/)
- [Architecture Decisions](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
