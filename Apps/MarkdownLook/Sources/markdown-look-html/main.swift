import Foundation
import MarkdownLookKit

// markdown-look-html FILE > page.html: the page the Quick Look preview would show for a Markdown or Mermaid file, for looking at it without Quick Look.
guard CommandLine.arguments.count == 2, let data = FileManager.default.contents(atPath: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: markdown-look-html FILE\n".utf8))
    exit(2)
}
let name = CommandLine.arguments[1].lowercased()
let title = (CommandLine.arguments[1] as NSString).lastPathComponent
let renderer = MarkdownHTMLRenderer()
let bytes = Array(data)
let isDiagram = name.hasSuffix(".mmd") || name.hasSuffix(".mermaid")
print(isDiagram ? renderer.diagramPage(bytes, title: title) : renderer.page(markdown: bytes, title: title))
