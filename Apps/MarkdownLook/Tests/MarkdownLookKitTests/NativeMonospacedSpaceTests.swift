import AppKit
import Testing

@testable import MarkdownLookKit

@Suite("NativeRichText.monospacedSpace")
struct NativeMonospacedSpaceTests {
    @Test func `returns a positive em width for every font face without CoreText typesetter dictionaries`() {
        for face in [FontFace.mono, .system, .serif, .rounded, .family("Menlo"), .family("Nonexistent Font 12345")] {
            var viewer = ViewerFonts()
            viewer.code = face
            let width = NativeRichText.monospacedSpace(NativeFonts(viewer))
            #expect(width > 0.1 && width < 2.0, "unexpected space width \(width) for \(face)")
        }
    }
}
