import AppKit
import MarkdownLookKit
import SwiftUI
import WebKit

/// A picture: RGBA, 8 bits, opaque (drawn over a fill).
struct Picture {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8)) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0 ..< width * height {
            pixels[index * 4] = fill.0
            pixels[index * 4 + 1] = fill.1
            pixels[index * 4 + 2] = fill.2
        }
    }

    /// `image` scaled to `width` pixels across and drawn from the top left over `fill`, in a picture of `width` by `height` pixels.
    init(_ image: CGImage, width: Int, height: Int, over fill: (UInt8, UInt8, UInt8)) {
        self.init(width: width, height: height, fill: fill)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let high = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: height - high, width: width, height: high))
        }
    }

    func png(to path: String) {
        var copy = pixels
        copy.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}

@MainActor final class WebLoader: NSObject, WKNavigationDelegate {
    var continuation: CheckedContinuation<Void, Never>?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
}

/// The web page, as WebKit draws it at `width` points (the oracle): a picture and the rectangles of its blocks.
@MainActor func webSnapshot(html: String, width: Int, dark: Bool, scale: Int) async -> (CGImage, [Block])? {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 800), configuration: WKWebViewConfiguration())
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    window.appearance = view.appearance
    window.setFrameOrigin(NSPoint(x: -4000, y: 0))
    window.makeKeyAndOrderFront(nil)
    let loader = WebLoader()
    view.navigationDelegate = loader
    await withCheckedContinuation { continuation in
        loader.continuation = continuation
        view.loadHTMLString(html, baseURL: nil)
    }
    try? await Task.sleep(for: .milliseconds(300))
    let height =
        (try? await view.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().bottom)") as? Int) ?? 800
    view.setFrameSize(NSSize(width: width, height: height))
    window.setContentSize(NSSize(width: width, height: height))
    try? await Task.sleep(for: .milliseconds(300))
    let script = """
        JSON.stringify([...document.querySelectorAll('main > *, li, td, th, blockquote > *, .alert > *, .footnote')].map(e => { const r = e.getBoundingClientRect(); \
        return [e.tagName.toLowerCase() + (e.className ? '.' + e.className : ''), r.left, r.top + scrollY, r.width, r.height]; }))
        """
    let json = (try? await view.evaluateJavaScript(script) as? String) ?? "[]"
    let blocks = Block.parse(json)
    let configuration = WKSnapshotConfiguration()
    configuration.rect = NSRect(x: 0, y: 0, width: width, height: height)
    configuration.snapshotWidth = NSNumber(value: width * scale)
    let image: NSImage? = await withCheckedContinuation { continuation in
        view.takeSnapshot(with: configuration) { image, _ in continuation.resume(returning: image) }
    }
    guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return (cg, blocks)
}

/// The same document drawn by the native view at `width` points, at the height it asks for.
@MainActor func nativeSnapshot(
    document: NativeDocument,
    settings: ViewerSettings,
    width: Int,
    dark: Bool,
    scale: Int
) async -> CGImage? {
    let host = NSHostingView(
        rootView: NativeDocumentColumn(document: document, settings: settings)
            .tint(Color(nsColor: .linkColor))
            .frame(width: CGFloat(width))
            .fixedSize(horizontal: false, vertical: true)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.setFrameOrigin(NSPoint(x: -4000, y: 0))
    window.makeKeyAndOrderFront(nil)
    host.layoutSubtreeIfNeeded()
    let height = Int(host.fittingSize.height.rounded(.up))
    window.setContentSize(NSSize(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    try? await Task.sleep(for: .milliseconds(400))
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width * scale,
            pixelsHigh: height * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else { return nil }
    rep.size = NSSize(width: width, height: height)
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.cgImage
}
