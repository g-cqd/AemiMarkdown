// swift Scripts/snapshot.swift page.html out.png [width] [height] [dark]: a web view off screen, loaded with the page and written as a PNG (the desktop is not captured).
import AppKit
import WebKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: snapshot.swift page.html out.png [width] [height] [dark]")
    exit(2)
}
let width = arguments.count > 3 ? Double(arguments[3]) ?? 900 : 900
let height = arguments.count > 4 ? Double(arguments[4]) ?? 1200 : 1200
let dark = arguments.contains("dark")
let selectAll = arguments.contains("select")

@MainActor final class Loader: NSObject, WKNavigationDelegate {
    let view: WKWebView
    init(view: WKWebView) { self.view = view }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if selectAll { webView.evaluateJavaScript("document.execCommand('selectAll')") { _, _ in } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            webView.takeSnapshot(with: nil) { image, _ in
                if let image, let tiff = image.tiffRepresentation,
                    let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                {
                    try? png.write(to: URL(fileURLWithPath: arguments[2]))
                }
                exit(0)
            }
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let configuration = WKWebViewConfiguration()
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    window.setFrameOrigin(NSPoint(x: -4000, y: 0))
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    window.appearance = view.appearance
    let loader = Loader(view: view)
    view.navigationDelegate = loader
    let html = (try? String(contentsOfFile: arguments[1], encoding: .utf8)) ?? ""
    view.loadHTMLString(html, baseURL: nil)
    objc_setAssociatedObject(view, "loader", loader, .OBJC_ASSOCIATION_RETAIN)
    application.run()
}
