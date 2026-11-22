import AemiMarkdown
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// An alert's symbol sits on the line of its title (the owner, 2026-11-22: "the symbol for notes, warning, information etc … is not
/// aligned vertically with the text that follows"): the symbol's ink is centred where the title's capitals are, as a symbol set in
/// the text would be, not standing on the baseline above them.
@MainActor @Suite("An alert's symbol is centred on its title", .serialized)
struct NativeAlertSymbolTests {
    /// The vertical extent, in points, of each run of coloured columns in the title row: the symbol first, then the title's first letter.
    private func inkRuns(_ alert: String) async throws -> [(top: Double, bottom: Double)] {
        _ = NSApplication.shared
        let source = "> [!\(alert)]\n> Body text."
        let document = NativeDocument(MarkdownParser.parse(Array(source.utf8)))
        let width = 600
        let scale = 2
        let host = NSHostingView(
            rootView: NativeDocumentColumn(document: document, settings: ViewerSettings()).frame(width: CGFloat(width))
                .fixedSize(horizontal: false, vertical: true)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let height = Int(host.fittingSize.height.rounded(.up))
        window.setContentSize(NSSize(width: width, height: height))
        host.layoutSubtreeIfNeeded()
        for _ in 0 ..< 16 { try? await Task.sleep(for: .milliseconds(25)) }
        let rep = try #require(
            NSBitmapImageRep(
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
        )
        rep.size = NSSize(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: rep)
        // Coloured ink: the alert's colour, never the grey or black of the body text, nor the white page.
        func coloured(_ x: Int, _ y: Int) -> Bool {
            guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            let parts = [colour.redComponent, colour.greenComponent, colour.blueComponent]
            return (parts.max() ?? 0) - (parts.min() ?? 0) > 0.25
        }
        // The title row: the first rows of pixels holding coloured ink right of the bar (which is the alert's colour too, at the column's 40 pt padding).
        let left = 48 * scale
        var rows: [Int] = []
        for y in 0 ..< rep.pixelsHigh where (left ..< rep.pixelsWide).contains(where: { coloured($0, y) }) {
            if let last = rows.last, y - last > 4 * scale { break }
            rows.append(y)
        }
        let band = try #require(rows.first) ... (try #require(rows.last))
        var runs: [(start: Int, end: Int, top: Int, bottom: Int)] = []
        for x in left ..< rep.pixelsWide {
            let ink = band.filter { coloured(x, $0) }
            guard let top = ink.first, let bottom = ink.last else { continue }
            // Of the title, only its first letter, a capital standing on the baseline: a later `p` or `g` would pull its centre down.
            if runs.count == 2, x - runs[1].start > 5 * scale { break }
            if let last = runs.last, x - last.end <= 3 * scale {
                runs[runs.count - 1] = (last.start, x, min(last.top, top), max(last.bottom, bottom))
            } else {
                runs.append((x, x, top, bottom))
            }
        }
        return runs.map { (Double($0.top) / Double(scale), Double($0.bottom) / Double(scale)) }
    }

    @Test(arguments: ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"])
    func `the symbol's ink is centred on the title's first capital, within half a point`(alert: String) async throws {
        let runs = try await inkRuns(alert)
        try #require(runs.count >= 2, "a symbol and a title: \(runs)")
        let symbol = (runs[0].top + runs[0].bottom) / 2
        let title = (runs[1].top + runs[1].bottom) / 2
        #expect(abs(symbol - title) <= 0.5, "symbol centre \(symbol), title centre \(title), runs \(runs)")
    }
}
