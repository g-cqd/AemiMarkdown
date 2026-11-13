internal import SwiftUI

/// A task's box as the style sheet draws it: 0.95 em square, a border of 1.5 points in the tertiary colour with corners of 0.28 em, and, when done, the border in the secondary colour and a check at 72 %
/// of the room inside. Drawn, not a symbol, which would not take the same size at every text size.
@available(macOS 26.0, *)
struct TaskBox: View {
    let done: Bool

    var body: some View {
        GeometryReader { box in
            let side = box.size.width
            ZStack {
                RoundedRectangle(cornerRadius: side / 0.95 * 0.28)
                    .strokeBorder(done ? NativeTheme.secondary : NativeTheme.tertiary, lineWidth: 1.5)
                if done {
                    let inner = (side - 3) * 0.72
                    Check().fill(NativeTheme.secondary).frame(width: inner, height: inner * 243 / 247)
                }
            }
        }
    }

    /// The check of the style sheet's picture (a 247 by 243 box), scaled to its frame.
    private struct Check: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x / 247 * rect.width, y: rect.minY + y / 243 * rect.height)
            }
            path.move(to: point(98, 230))
            path.addCurve(to: point(113, 222), control1: point(104, 230), control2: point(109, 227))
            path.addLine(to: point(230, 39))
            path.addCurve(to: point(234, 28), control1: point(233, 35), control2: point(234, 31))
            path.addCurve(to: point(219, 13), control1: point(234, 19), control2: point(228, 13))
            path.addCurve(to: point(205, 21), control1: point(213, 13), control2: point(209, 15))
            path.addLine(to: point(97, 194))
            path.addLine(to: point(41, 122))
            path.addCurve(to: point(28, 115), control1: point(37, 117), control2: point(33, 115))
            path.addCurve(to: point(13, 130), control1: point(19, 115), control2: point(13, 121))
            path.addCurve(to: point(18, 141), control1: point(13, 134), control2: point(14, 138))
            path.addLine(to: point(83, 222))
            path.addCurve(to: point(98, 230), control1: point(87, 227), control2: point(92, 230))
            path.closeSubpath()
            return path
        }
    }
}
