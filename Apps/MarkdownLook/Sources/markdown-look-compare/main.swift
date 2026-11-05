import AemiMarkdown
import AppKit
import Foundation
import MarkdownLookKit

// markdown-look-compare FILE.md [--width N] [--dark] [--scale N] [--out DIR] [--text-size N] [--blocks] [--typeface system|serif|serifDisplay|serifText] [--text-font F] [--heading-font F] [--code-font F] [--features ss01,tnum] [--columns] [--bleed] [--left] [--scroll-tables] [--outline] [--column-lines]: the page as HTML in WebKit (the oracle) and as the native view, at one width, with a measure of how alike they are.
let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
let width = Int(option("--width") ?? "") ?? 800
let scale = Int(option("--scale") ?? "") ?? 2
let dark = arguments.contains("--dark")
let outDirectory = option("--out") ?? "/tmp/ql/compare"
guard let path = arguments.first(where: { !$0.hasPrefix("--") && FileManager.default.fileExists(atPath: $0) }),
    let data = FileManager.default.contents(atPath: path)
else {
    print(
        "usage: markdown-look-compare FILE.md [--width N] [--dark] [--scale N] [--out DIR] [--text-size N] [--blocks] [--columns] [--bleed] [--left] [--scroll-tables] [--outline] [--column-lines]"
    )
    exit(2)
}
try? FileManager.default.createDirectory(atPath: outDirectory, withIntermediateDirectories: true)
var settings = ViewerSettings()
if let size = option("--text-size").flatMap(Int.init) { settings.textSize = size }
// The choices a person may have made in the Settings window, by name.
if arguments.contains("--scroll-tables") { settings.scrollsTables = true }
if let name = option("--typeface"), let preset = ViewerFonts.Preset(rawValue: name) { settings.fonts = preset.fonts }
if let name = option("--text-font") { settings.fonts.text = FontFace(name) }
if let name = option("--heading-font") { settings.fonts.heading = FontFace(name) }
if let name = option("--code-font") { settings.fonts.code = FontFace(name) }
if let words = option("--features") { settings.fonts.features = ViewerFonts.features(words) }
if arguments.contains("--bleed") { settings.bleedsTables = true }
if arguments.contains("--left") { settings.alignsLeft = true }
if arguments.contains("--outline") { settings.outerBorder = true }
if arguments.contains("--column-lines") { settings.columnLines = true }
settings.copyButton = false
let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
let fill: (UInt8, UInt8, UInt8) = dark ? (30, 30, 30) : (255, 255, 255)

func describe(_ band: Band?) -> String {
    guard let band else { return "-" }
    let s = Double(scale)
    return String(
        format: "%6.1f-%6.1f x %5.1f-%5.1f",
        Double(band.top) / s,
        Double(band.bottom + 1) / s,
        Double(band.left) / s,
        Double(band.right + 1) / s
    )
}

@MainActor func run() async {
    let bytes = Array(data)
    let page = MarkdownHTMLRenderer(settings: settings).page(markdown: bytes, title: name)
    let native = NativeDocument(MarkdownParser.parse(bytes), settings: settings)
    guard let (web, blocks) = await webSnapshot(html: page, width: width, dark: dark, scale: scale),
        let drawn = await nativeSnapshot(document: native, settings: settings, width: width, dark: dark, scale: scale)
    else {
        print("could not draw")
        exit(1)
    }
    // Both are drawn at `width * scale` pixels across, whatever scale the screen gave them.
    func high(_ image: CGImage) -> Int {
        Int((Double(image.height) * Double(width * scale) / Double(image.width)).rounded())
    }
    let height = max(high(web), high(drawn))
    let a = Picture(web, width: width * scale, height: height, over: fill)
    let b = Picture(drawn, width: width * scale, height: height, over: fill)
    a.png(to: "\(outDirectory)/\(name)-web.png")
    b.png(to: "\(outDirectory)/\(name)-native.png")
    Picture.panel(a, b).png(to: "\(outDirectory)/\(name)-panel.png")
    let s = similarity(a, b, fill: fill)
    print(
        String(
            format: "%@  width %d pt  height web %.1f native %.1f  similarity exact %.1f%% blurred %.1f%%",
            name,
            width,
            Double(high(web)) / Double(scale),
            Double(high(drawn)) / Double(scale),
            s.exact * 100,
            s.blurred * 100
        )
    )
    let bandsA = a.bands(fill: fill)
    let bandsB = b.bands(fill: fill)
    print("bands in points (top-bottom x left-right): web | native | delta top bottom left right")
    for index in 0 ..< max(bandsA.count, bandsB.count) {
        let x = index < bandsA.count ? bandsA[index] : nil
        let y = index < bandsB.count ? bandsB[index] : nil
        var delta = ""
        if let x, let y {
            let d = Double(scale)
            delta = String(
                format: "%+5.1f %+5.1f %+5.1f %+5.1f",
                Double(y.top - x.top) / d,
                Double(y.bottom - x.bottom) / d,
                Double(y.left - x.left) / d,
                Double(y.right - x.right) / d
            )
        }
        print("\(describe(x)) | \(describe(y)) | \(delta)")
    }
    if arguments.contains("--columns") {
        // Each table's column rules in points, in the page and in the native view (turn on `--column-lines`).
        for block in blocks where block.name.hasPrefix("div.table-wrap") {
            let top = Int((block.y + 6) * Double(scale))
            let bottom = Int((block.y + block.height - 6) * Double(scale))
            func points(_ picture: Picture) -> String {
                picture.verticalLines(fill: fill, top: top, bottom: bottom)
                    .map {
                        String(format: "%.1f", Double($0) / Double(scale))
                    }
                    .joined(separator: " ")
            }
            print("table y \(Int(block.y)): web [\(points(a))]  native [\(points(b))]")
        }
    }
    if arguments.contains("--blocks") {
        for block in blocks {
            print(
                String(
                    format: "%@ x %.1f y %.1f w %.1f h %.1f",
                    block.name,
                    block.x,
                    block.y,
                    block.width,
                    block.height
                )
            )
        }
    }
    exit(0)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    Task { @MainActor in await run() }
    application.run()
}
