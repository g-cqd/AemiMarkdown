import Foundation
import MarkdownLookKit

// markdown-look-html FILE > page.html: the page the Quick Look preview would show for a Markdown or Mermaid file, for looking at it without Quick Look.
let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
guard paths.count == 1, let data = FileManager.default.contents(atPath: paths[0]) else {
    FileHandle.standardError.write(Data("usage: markdown-look-html FILE\n".utf8))
    exit(2)
}
let name = paths[0].lowercased()
let title = (paths[0] as NSString).lastPathComponent
// The reader's own choices (the app's preferences), as the preview shows them; `--defaults` ignores them.
let renderer = MarkdownHTMLRenderer(
    settings: CommandLine.arguments.contains("--defaults") ? ViewerSettings() : ViewerSettings.current()
)
let bytes = Array(data)
let isDiagram = name.hasSuffix(".mmd") || name.hasSuffix(".mermaid")
print(isDiagram ? renderer.diagramPage(bytes, title: title) : renderer.page(markdown: bytes, title: title))
