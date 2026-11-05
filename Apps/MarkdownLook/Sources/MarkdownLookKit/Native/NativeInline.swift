internal import AemiMarkdown
internal import Foundation
internal import SwiftUI

/// The inline content of one leaf block as styled text: emphasis, strong, strikethrough, code, links (only where `HTMLText.isSafeDestination` allows), footnote references that link to their
/// notes, images named and not loaded.
struct NativeInline {
    private(set) var string = AttributedString()
    /// The labels of the footnotes referenced, in order.
    private(set) var notes: [String] = []
    private var strong = 0
    private var emphasis = 0
    private var strike = 0
    private var code = 0
    private var image = 0
    private var link: URL?
    private var inLink = false
    private var autolinkKind: Int?
    private var smart: SmartPunctuation?

    init(smartPunctuation: Bool) { smart = smartPunctuation ? SmartPunctuation() : nil }

    var isEmpty: Bool { string.characters.isEmpty }

    mutating func enter(_ node: MarkdownNode) {
        switch node.kind {
            case .emphasis: emphasis += 1
            case .strong: strong += 1
            case .strikethrough: strike += 1
            case .codeSpan, .math: code += 1
            case .link:
                inLink = true
                link = nil
            case .image:
                image += 1
                append("\u{25A3}\u{00A0}")
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
                link = inLink && HTMLText.isSafeDestination(destination) ? URL(string: destination) : nil
            case .text:
                if let kind = autolinkKind {
                    appendAutolink(text(node.range), kind: kind)
                } else {
                    append(text(node.range), smartly: true)
                }
            case .entity: append(String(decoding: document.decode(node.range), as: UTF8.self))
            case .htmlInline: append(text(node.range))
            case .softBreak: append(" ")
            case .hardBreak: append("\n")
            case .footnoteReference:
                let label = text(node.range)
                notes.append(label)
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
