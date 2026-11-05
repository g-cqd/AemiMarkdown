import AemiMarkdown
import Foundation
import Markdown
import MarkdownLookKit

// Every engine reads the same files, converts each to HTML (or, where it has no HTML writer, to its tree), for `rounds` rounds on one thread; the best round's CPU time is the figure.
// usage: CompareSwift DIR [--rounds N] [--engine NAME]
let arguments = CommandLine.arguments
func option(_ name: String) -> String? {
    arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
}
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: CompareSwift DIR [--rounds N] [--engine NAME]\n".utf8))
    exit(2)
}
let directory = arguments[1]
let rounds = option("--rounds").flatMap(Int.init) ?? 5
let only = option("--engine")
var loaded: [[UInt8]] = []
for name in ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted() {
    if let data = FileManager.default.contents(atPath: directory + "/" + name) { loaded.append(Array(data)) }
}
let documents = loaded
let total = documents.reduce(0) { $0 + $1.count }

func cpu() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

/// Runs `convert` on every document, `rounds` times after one warm-up, and prints one JSON line.
func measure(_ name: String, _ version: String, _ what: String, _ convert: ([UInt8]) -> Int) {
    if let only, only != name { return }
    var out = 0
    for document in documents { out += convert(document) }
    var best = Double.infinity
    for _ in 0 ..< rounds {
        let start = cpu()
        var produced = 0
        for document in documents { produced += convert(document) }
        best = Swift.min(best, cpu() - start)
        out = produced
    }
    let line =
        "{\"engine\":\"\(name)\",\"version\":\"\(version)\",\"what\":\"\(what)\",\"documents\":\(documents.count),\"bytes\":\(total),\"seconds\":\(best),\"mbps\":\(Double(total) / best / 1e6),\"output_bytes\":\(out)}"
    print(line)
}

// --dump OUT: writes each document's HTML twice (the plain settings of the benchmark, and the viewer's defaults: highlighting, smart punctuation, diagrams) as OUT/NAME.plain.html and OUT/NAME.default.html,
// so that a change to the writer can be shown to change no byte.
if let out = option("--dump") {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    var plainSettings = ViewerSettings()
    plainSettings.drawsDiagrams = false
    plainSettings.highlightsCode = false
    plainSettings.smartPunctuation = false
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
    for (name, bytes) in zip(names, documents) {
        let document = MarkdownParser.parse(bytes)
        let plainHTML = MarkdownHTMLRenderer(settings: plainSettings).body(document, embedsDiagramStyle: false)
        let defaultHTML = MarkdownHTMLRenderer(settings: ViewerSettings()).body(document, embedsDiagramStyle: false)
        try? plainHTML.write(toFile: out + "/" + name + ".plain.html", atomically: true, encoding: .utf8)
        try? defaultHTML.write(toFile: out + "/" + name + ".default.html", atomically: true, encoding: .utf8)
    }
    exit(0)
}

var plain = ViewerSettings()
plain.drawsDiagrams = false
plain.highlightsCode = false
plain.smartPunctuation = false
let renderer = MarkdownHTMLRenderer(settings: plain)

measure("aemimarkdown-parse", "local", "tree") { bytes in
    MarkdownParser.parse(bytes).source.count
}
measure("aemimarkdown-html", "local", "html") { bytes in
    renderer.body(MarkdownParser.parse(bytes), embedsDiagramStyle: false).utf8.count
}
measure("swift-markdown-parse", "ea1d88b", "tree") { bytes in
    Document(parsing: String(decoding: bytes, as: UTF8.self)).childCount
}
measure("swift-markdown-html", "ea1d88b", "html") { bytes in
    var formatter = HTMLFormatter()
    formatter.visit(Document(parsing: String(decoding: bytes, as: UTF8.self)))
    return formatter.result.utf8.count
}
measure("foundation-attributedstring", "system", "tree") { bytes in
    let text = String(decoding: bytes, as: UTF8.self)
    return ((try? AttributedString(markdown: text)) ?? AttributedString()).characters.count
}
