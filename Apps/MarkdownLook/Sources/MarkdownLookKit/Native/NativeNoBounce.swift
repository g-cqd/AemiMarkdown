internal import AppKit
internal import SwiftUI

/// Stops the scroll view around a view from bouncing: SwiftUI's `scrollBounceBehavior` can only bounce "always" or "when the content is larger", and a table that is wider than the page should stop at
/// its edge as it does in the page, not give way and spring back. The view sits in the scroll view's content, so the first scroll view above it is the one; its elasticity is turned off on both axes.
@available(macOS 26.0, *)
struct NoBounce: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.lock() }

    final class Probe: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            lock()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            lock()
        }

        func lock() {
            guard let scroll = enclosingScrollView else { return }
            scroll.horizontalScrollElasticity = .none
            scroll.verticalScrollElasticity = .none
        }
    }
}
