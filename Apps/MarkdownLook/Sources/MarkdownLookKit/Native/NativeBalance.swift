internal import AppKit
internal import CoreText
public import SwiftUI

/// A block of text laid out as the page lays it out: a whole number of lines of the exact height, and for a heading `text-wrap: balance`: the lines of a wrapped heading as even as they can be without taking another line. The narrowest width at which the text still wraps into as many lines as it does
/// at the full width, found by halving (about ten greedy passes of the typesetter, each linear in the text), and the text is laid out at that width.
struct BalancedLayout: Layout {
    /// The height of a line as the page sets it: a page's lines are exactly this far apart, where SwiftUI rounds each line up to the pixel grid, so a block is this many lines high and no more.
    let lineHeight: CGFloat
    /// What to balance: nothing for prose, a heading's text and font.
    var text = ""
    var font = NSFont.systemFont(ofSize: 13)
    var kern: CGFloat = 0
    var balances = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let width = balancedWidth(in: proposal.width)
        let fit = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let lines = Swift.max(1, (fit.height / lineHeight).rounded())
        return CGSize(width: proposal.width ?? fit.width, height: lines * lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let view = subviews.first else { return }
        let width = balancedWidth(in: bounds.width)
        view.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }

    private func balancedWidth(in available: CGFloat?) -> CGFloat? {
        guard balances, let available, available.isFinite, available > 0, !text.contains("\n") else { return available }
        let typesetter = CTTypesetterCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font, .kern: kern]) as CFAttributedString
        )
        let length = (text as NSString).length
        func lines(at width: CGFloat) -> Int {
            var start = 0
            var count = 0
            while start < length {
                let step = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
                start += Swift.max(1, step)
                count += 1
            }
            return count
        }
        let target = lines(at: available)
        guard target > 1 else { return available }
        var low = available / CGFloat(target)
        var high = available
        while high - low > 0.5 {
            let middle = (low + high) / 2
            if lines(at: middle) > target { low = middle } else { high = middle }
        }
        return Swift.min(available, high + 0.5)
    }
}
