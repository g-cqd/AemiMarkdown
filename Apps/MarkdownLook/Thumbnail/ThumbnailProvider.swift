import CoreGraphics
import CoreText
import Foundation
import MarkdownLookKit
import QuickLookThumbnailing

/// The Quick Look thumbnail for Markdown and Mermaid files: a page with the start of the text, headings heavier, drawn with CoreText and no web view (a thumbnail runs in a small budget).
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        let size = request.maximumSize
        let side = Swift.min(size.width, size.height)
        let page = CGSize(width: (side * 0.78).rounded(), height: side)
        let url = request.fileURL
        handler(
            QLThumbnailReply(contextSize: page) { context in
                guard let handle = try? FileHandle(forReadingFrom: url), let data = try? handle.read(upToCount: 65536)
                else { return false }
                try? handle.close()
                // The context may be in pixels while the size is in points: scale to the size.
                let device = context.convertToDeviceSpace(CGSize(width: 1, height: 1))
                let wanted = context.width > 0 ? Double(context.width) / page.width : device.width
                if device.width > 0, abs(wanted - device.width) > 0.01 {
                    context.scaleBy(x: wanted / device.width, y: wanted / device.width)
                }
                let name = url.lastPathComponent.lowercased()
                if name.hasSuffix(".mmd") || name.hasSuffix(".mermaid"),
                    DiagramThumbnail.draw(Array(data), in: context, size: page)
                {
                    return true
                }
                PageDrawing.draw(String(decoding: data, as: UTF8.self), in: context, size: page)
                return true
            },
            nil
        )
    }
}

enum PageDrawing {
    /// The first lines of `text` on a white page: `#` headings in semibold at a larger size, the rest regular, fences and tables in monospace.
    static func draw(_ text: String, in context: CGContext, size: CGSize) {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let margin = size.width * 0.09
        let body = Swift.max(5, size.width * 0.052)
        var y = size.height - margin
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(60) {
            let line = String(raw)
            let heading = line.prefix { $0 == "#" }.count
            let isCode = line.hasPrefix("    ") || line.hasPrefix("```") || line.hasPrefix("|")
            let fontSize = heading > 0 ? body * (1.9 - Double(Swift.min(heading, 4)) * 0.15) : body
            let font = CTFontCreateUIFontForLanguage(
                isCode ? .userFixedPitch : (heading > 0 ? .emphasizedSystem : .system),
                fontSize,
                nil
            )
            let shown = heading > 0 ? String(line.drop { $0 == "#" || $0 == " " }) : line
            guard !shown.isEmpty else {
                y -= body * 0.7
                continue
            }
            y -= fontSize * 1.3
            if y < margin { break }
            let attributed = CFAttributedStringCreateMutable(nil, 0)
            CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), shown as CFString)
            let range = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
            CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName, font)
            CFAttributedStringSetAttribute(
                attributed,
                range,
                kCTForegroundColorAttributeName,
                CGColor(gray: heading > 0 ? 0.1 : 0.3, alpha: 1)
            )
            let ctLine = CTLineCreateWithAttributedString(attributed!)
            let width = size.width - margin * 2
            let fitted =
                CTLineCreateTruncatedLine(
                    ctLine,
                    width,
                    .end,
                    CTLineCreateWithAttributedString(NSAttributedString(string: "…") as CFAttributedString)
                ) ?? ctLine
            context.textPosition = CGPoint(x: margin, y: y)
            CTLineDraw(fitted, context)
        }
    }
}
