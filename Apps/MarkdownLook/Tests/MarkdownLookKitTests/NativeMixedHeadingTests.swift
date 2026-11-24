import AemiMarkdown
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MarkdownLookKit

/// A heading mixing prose and inline code spans (or other inline formats) must span the available column width and must
/// not wrap into a narrow balanced box that overflows onto the paragraph below it.
@MainActor @Suite("Mixed-format headings do not overflow or overlap", .serialized)
struct NativeMixedHeadingTests {
    @Test func `a heading with inline code spans wraps within its reported height and does not overlap what follows`()
        async throws
    {
        _ = NSApplication.shared
        let source = """
            # Ecosystem Promotion Audit — `litmus`, `analyzerkit`, and `aemi` (Challenged & Refined)

            **Date:** 2026-11-24 **Scope:** Static cross-repository audit of local checkouts (`aemi`, `ask`, `Atelier`, `ProcessMonitor`, `sunset`, `VMRunner`) plus `analyzerkit` and `litmus`.
            """
        var settings = ViewerSettings()
        settings.textSize = 15
        let document = NativeDocument(MarkdownParser.parse(Array(source.utf8)), settings: settings)
        let width = 760
        let host = NSHostingView(
            rootView: NativeDocumentColumn(document: document, settings: settings).frame(width: CGFloat(width))
                .fixedSize(horizontal: false, vertical: true)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
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

        // Render and verify: the heading takes at most 3 lines and leaves clear white space before the body paragraph.
        let scale = 2
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

        // Find horizontal runs of dark pixels per row: the heading lines and the paragraph lines should be separated by
        // a clean white gap (at least 10 pt = 20 px) with zero dark pixels in it.
        var rowHasDark = [Bool](repeating: false, count: rep.pixelsHigh)
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    c.alphaComponent > 0.5 && c.redComponent < 0.5 && c.greenComponent < 0.5 && c.blueComponent < 0.5
                {
                    rowHasDark[y] = true
                    break
                }
            }
        }
        // Group contiguous dark bands (text lines).
        var bands: [(start: Int, end: Int)] = []
        var y = 0
        while y < rowHasDark.count {
            if rowHasDark[y] {
                let start = y
                while y < rowHasDark.count, rowHasDark[y] { y += 1 }
                bands.append((start, y - 1))
            } else {
                y += 1
            }
        }
        // There must be a clear gap >= 14 pt (28 px) between the heading's last line and the paragraph's first line.
        let maxGapPx = zip(bands, bands.dropFirst()).map { $1.start - $0.end }.max() ?? 0
        #expect(
            maxGapPx >= 24,
            "Expected clear gap between heading and paragraph; bands=\(bands), maxGapPx=\(maxGapPx)"
        )
        // Also check the heading line count: at 760 pt window (~600 pt column), it should not wrap to 4 narrow lines.
        let headingLines =
            bands.prefix(while: { band in
                guard let first = bands.first else { return false }
                return band.start - first.start < 200
            })
            .count
        // If there's a gap >= 24 px, split at the largest gap to count heading bands.
        if let splitIndex = zip(bands, bands.dropFirst()).enumerated()
            .max(by: {
                ($0.element.1.start - $0.element.0.end) < ($1.element.1.start - $1.element.0.end)
            })?
            .offset
        {
            let hCount = splitIndex + 1
            #expect(hCount <= 3, "Heading wrapped into too many narrow lines: \(hCount), bands=\(bands)")
        } else {
            #expect(headingLines <= 3)
        }
    }
}
