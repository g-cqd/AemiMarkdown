internal import AemiMarkdown
internal import Foundation
internal import SwiftUI

/// The inline content of one leaf block as styled text: emphasis, strong, strikethrough, code, links (only where `HTMLText.isSafeDestination` allows), footnote references that link to their
/// notes, images named and not loaded (a paragraph that is one image becomes a row of its own: `soleImage`).
@available(macOS 26.0, *)
struct NativeInline {
    private(set) var string = AttributedString()
    /// The labels of the footnotes referenced, in order.
    private(set) var notes: [String] = []
    private var strong = 0
    private var emphasis = 0
    private var strike = 0
    private var code = 0
    private var image = 0
    /// The images met, with what each is inside of.
    private var images: [NativeImage] = []
    /// Something shows besides images: words, a note's reference.
    private var hasWords = false
    private var imageInLink = false
    private var link: URL?
    private var inLink = false
    private var autolinkKind: Int?
    private var smart: SmartPunctuation?
    /// Drops a soft break or leading spaces right after an HTML `<br>` tag (matching HTML whitespace collapsing).
    private var trimAfterBreak = false

    init(smartPunctuation: Bool) { smart = smartPunctuation ? SmartPunctuation() : nil }

    var isEmpty: Bool { string.characters.isEmpty }

    /// The image this block is, when it is one image and nothing else (it may be inside a link).
    var soleImage: NativeImage? {
        guard images.count == 1, !hasWords, var only = images.first else { return nil }
        only.fallback = string
        return only
    }

    mutating func enter(_ node: MarkdownNode) {
        switch node.kind {
            case .emphasis: emphasis += 1
            case .strong: strong += 1
            case .strikethrough: strike += 1
            case .codeSpan, .math:
                trimAfterBreak = false
                code += 1
            case .link:
                inLink = true
                link = nil
            case .image:
                image += 1
                append("\u{25A3}\u{00A0}")
                if image == 1 {
                    images.append(NativeImage(source: "", alt: "", fallback: AttributedString()))
                    imageInLink = imageInLink || inLink
                }
            case .autolink: autolinkKind = node.payload
            default: break
        }
    }

    mutating func exit(_ node: MarkdownNode) {
        switch node.kind {
            case .emphasis: emphasis -= 1
            case .strong: strong -= 1
            case .strikethrough: strike -= 1
            case .codeSpan, .math: code -= 1
            case .link:
                // An image inside this link leads where the link does (the destination is known by now, whichever came first).
                if imageInLink, let last = images.indices.last { images[last].link = link }
                imageInLink = false
                inLink = false
                link = nil
            case .image: image -= 1
            case .autolink: autolinkKind = nil
            default: break
        }
    }

    mutating func leaf(_ node: MarkdownNode, in document: MarkdownDocument) {
        func text(_ range: Range<Int>) -> String { String(decoding: document.source[range], as: UTF8.self) }
        switch node.kind {
            case .linkDestination:
                let destination = String(decoding: document.decode(node.range), as: UTF8.self)
                if image > 0 {
                    // The image's own destination: its file, not where its text leads.
                    if image == 1, let last = images.indices.last { images[last].source = destination }
                } else {
                    link = inLink && HTMLText.isSafeDestination(destination) ? URL(string: destination) : nil
                }
            case .text:
                if let kind = autolinkKind {
                    trimAfterBreak = false
                    appendAutolink(text(node.range), kind: kind)
                } else {
                    var piece = text(node.range)
                    if trimAfterBreak, code == 0 {
                        piece = String(piece.drop { $0 == " " || $0 == "\t" })
                        if !piece.isEmpty { trimAfterBreak = false }
                    } else {
                        trimAfterBreak = false
                    }
                    append(piece, smartly: true)
                }
            case .entity:
                trimAfterBreak = false
                append(String(decoding: document.decode(node.range), as: UTF8.self))
            case .htmlInline:
                if SafeHTML.isLineBreak(document.source[node.range]) {
                    append("\n")
                    trimAfterBreak = true
                } else {
                    trimAfterBreak = false
                    append(text(node.range))
                }
            case .softBreak:
                if trimAfterBreak {
                    // `<br>\nnext` already broke the line; avoid inserting a leading space on the new line.
                } else {
                    append(" ")
                }
            case .hardBreak:
                trimAfterBreak = false
                append("\n")
            case .footnoteReference:
                trimAfterBreak = false
                let label = text(node.range)
                notes.append(label)
                hasWords = true
                var run = AttributedString(label)
                run.link = NativeLink.url(NativeLink.note, label: label)
                string.append(run)
            default: break
        }
    }

    mutating func appendPlain(_ text: String, link target: URL? = nil, secondary: Bool = false) {
        var run = AttributedString(text)
        if let target { run.link = target }
        if secondary { run.foregroundColor = NativeTheme.secondary }
        if !text.allSatisfy(\.isWhitespace) { hasWords = true }
        string.append(run)
    }

    private mutating func appendAutolink(_ shown: String, kind: Int) {
        var target = shown
        if kind == 1, !shown.hasPrefix("mailto:") { target = "mailto:" + shown }
        if kind == 2, !shown.contains(":") { target = "http://" + shown }
        let previous = link
        link = HTMLText.isSafeDestination(target) ? URL(string: target) : nil
        // A page breaks a line at a space, not inside an address; the text engine also breaks after a slash, which a word joiner prevents.
        append(shown.replacing("/", with: "/\u{2060}"))
        link = previous
    }

    private mutating func append(_ text: String, smartly: Bool = false) {
        guard !text.isEmpty else { return }
        if image == 0 {
            if !text.allSatisfy(\.isWhitespace) { hasWords = true }
        } else if image == 1, let last = images.indices.last, text != "\u{25A3}\u{00A0}" {
            images[last].alt += text
        }
        let shown = smartly && code == 0 && image == 0 ? (smart?.apply(text) ?? text) : text
        var run = AttributedString(shown)
        var intent: InlinePresentationIntent = []
        if strong > 0 { intent.insert(.stronglyEmphasized) }
        if emphasis > 0 { intent.insert(.emphasized) }
        if code > 0 { intent.insert(.code) }
        if !intent.isEmpty { run.inlinePresentationIntent = intent }
        if strike > 0 {
            run.strikethroughStyle = .single
            run.foregroundColor = NativeTheme.secondary
        }
        if image > 0 { run.foregroundColor = NativeTheme.secondary }
        if let link { run.link = link }
        string.append(run)
    }
}
