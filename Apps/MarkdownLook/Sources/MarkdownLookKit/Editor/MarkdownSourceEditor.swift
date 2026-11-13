public import AppKit
public import SwiftUI

/// A plain-text editor on a `MarkdownSource` (ADR-0008): the source's own text storage, so every editor of a source shows and
/// edits the same text and they share one undo history; the Markdown is coloured where it is shown. It holds no text of its own.
@available(macOS 26.0, *)
public struct MarkdownSourceEditor: NSViewRepresentable {
    public let source: MarkdownSource
    public var configuration: MarkdownEditorConfiguration
    public var proxy: MarkdownEditorProxy?

    public init(
        source: MarkdownSource,
        configuration: MarkdownEditorConfiguration = MarkdownEditorConfiguration(),
        proxy: MarkdownEditorProxy? = nil
    ) {
        self.source = source
        self.configuration = configuration
        self.proxy = proxy
    }

    public func makeCoordinator() -> MarkdownSourceEditorCoordinator {
        MarkdownSourceEditorCoordinator(source: source, configuration: configuration)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let view = Self.makeTextView(for: source, configuration: configuration)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = view
        view.delegate = context.coordinator
        context.coordinator.attach(view, in: scroll, proxy: proxy)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(configuration, proxy: proxy)
    }

    public static func dismantleNSView(_ scroll: NSScrollView, coordinator: MarkdownSourceEditorCoordinator) {
        coordinator.detach()
    }

    /// A text view on the source's storage, with a layout of its own: plain text, no substitutions, undo through its delegate.
    @MainActor
    public static func makeTextView(
        for source: MarkdownSource,
        configuration: MarkdownEditorConfiguration
    ) -> NSTextView {
        let layout = NSLayoutManager()
        source.storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let view = NSTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.font = .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        view.textContainerInset = configuration.inset
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        return view
    }

    /// Takes a text view made by `makeTextView` off the source's storage (the view is going away).
    @MainActor
    public static func detach(_ view: NSTextView, from source: MarkdownSource) {
        // AppKit declares the property unowned(unsafe); the view is alive here, and so is the layout it owns.
        if let layout = unsafe view.layoutManager { source.storage.removeLayoutManager(layout) }
    }
}
