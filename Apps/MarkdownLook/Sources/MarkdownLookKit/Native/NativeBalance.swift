public import SwiftUI

/// A block of text laid out as the page lays it out: a whole number of lines of the exact height, and for a heading
/// `text-wrap: balance`: the lines of a wrapped heading as even as they can be without taking another line. Measured
/// against the SwiftUI text view itself (so headings mixing code spans, links, emphasis or footnotes balance at their
/// real rendered width, never wrapping into a narrower box that overflows onto what follows).
@available(macOS 26.0, *)
struct BalancedLayout: Layout {
    /// The height of a line as the page sets it: a page's lines are exactly this far apart, where SwiftUI rounds each
    /// line up to the pixel grid, so a block is this many lines high and no more.
    let lineHeight: CGFloat
    /// Whether to balance wrapped lines (true for headings, false for prose).
    var balances = false
    /// Whether the text contains an explicit newline (explicit line breaks are not balanced).
    var hasNewline = false

    struct Cache {
        var lastAvailable: CGFloat?
        var lastBalanced: CGFloat?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let width = balancedWidth(for: view, in: proposal.width, cache: &cache)
        let fit = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let lines = Swift.max(1, (fit.height / lineHeight).rounded())
        return CGSize(width: fit.width, height: lines * lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard let view = subviews.first else { return }
        // Use the same width that `sizeThatFits` computed (`bounds.width` is already `fit.width`, which may be narrower
        // than the column; running `balancedWidth` again on `fit.width` would shrink a multi-line heading a second time).
        let width: CGFloat? =
            if let cached = cache.lastBalanced, cached <= bounds.width + 1 {
                cached
            } else {
                bounds.width
            }
        view.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }

    private func balancedWidth(for view: LayoutSubview, in available: CGFloat?, cache: inout Cache) -> CGFloat? {
        guard balances, !hasNewline, let available, available.isFinite, available > 0 else { return available }
        if cache.lastAvailable == available, let cached = cache.lastBalanced { return cached }
        func lines(at width: CGFloat) -> Int {
            let h = view.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            return Swift.max(1, Int((h / lineHeight).rounded()))
        }
        let target = lines(at: available)
        guard target > 1 else {
            cache.lastAvailable = available
            cache.lastBalanced = available
            return available
        }
        var low = available / CGFloat(target)
        var high = available
        while high - low > 0.5 {
            let middle = (low + high) / 2
            if lines(at: middle) > target { low = middle } else { high = middle }
        }
        let result = Swift.min(available, high + 0.5)
        cache.lastAvailable = available
        cache.lastBalanced = result
        return result
    }
}
