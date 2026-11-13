internal import AemiMermaidLayout
internal import AemiMermaidScene
internal import AemiMermaidSyntax
public import CoreGraphics
internal import CoreText
internal import Foundation

/// A Mermaid diagram drawn straight into a CoreGraphics context for a thumbnail (ADR 0004): the same scene the SVG is made from, with no web view, which a thumbnail's small budget cannot afford.
/// Vector all the way: the context decides the pixels.
@available(macOS 26.0, *)
public struct DiagramThumbnail {
    private let scene: DiagramScene
    private let context: CGContext
    private let cell = CGSize(width: 9, height: 18)
    private let ink = CGColor(gray: 0.25, alpha: 1)

    /// Draws `source` centred in `size` on a white page, as large as fits. False when the source is not a diagram this engine draws (a pie chart is not drawn here yet).
    public static func draw(_ source: [UInt8], in context: CGContext, size: CGSize) -> Bool {
        let parse = MermaidParse.parse(source, limits: .default)
        if case .pie(let pie) = parse.result { return drawPie(pie, in: context, size: size) }
        var scene = DiagramScene()
        guard case .drawn = MermaidLayout.lay(parse.result, limits: .default, into: &scene), scene.width > 0,
            scene.height > 0
        else { return false }
        DiagramThumbnail(scene: scene, context: context).draw(size: size)
        return true
    }

    /// The muted tones of the vector style's pie, in order.
    private static let tones: [CGColor] = [
        (0.42, 0.50, 0.60), (0.56, 0.68, 0.62), (0.80, 0.73, 0.56), (0.75, 0.56, 0.53), (0.64, 0.58, 0.74),
        (0.53, 0.68, 0.75), (0.85, 0.80, 0.65), (0.66, 0.62, 0.58)
    ]
    .map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }

    /// A pie chart as sectors, no legend (a thumbnail is too small to read one).
    private static func drawPie(_ pie: PieDiagram, in context: CGContext, size: CGSize) -> Bool {
        let total = pie.slices.reduce(0) { $0 + $1.value }
        guard total > 0 else { return false }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let radius = Swift.min(size.width, size.height) * 0.36
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        var angle = Double.pi / 2
        for (index, slice) in pie.slices.enumerated() {
            let sweep = slice.value / total * 2 * Double.pi
            context.beginPath()
            context.move(to: centre)
            context.addArc(center: centre, radius: radius, startAngle: angle, endAngle: angle - sweep, clockwise: true)
            context.closePath()
            context.setFillColor(tones[index % tones.count])
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(1.5)
            context.drawPath(using: .fillStroke)
            angle -= sweep
        }
        return true
    }

    private func draw(size: CGSize) {
        let natural = CGSize(width: Double(scene.width) * cell.width, height: Double(scene.height) * cell.height)
        let margin = Swift.min(size.width, size.height) * 0.08
        let fit = Swift.min((size.width - 2 * margin) / natural.width, (size.height - 2 * margin) / natural.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.saveGState()
        // Scene coordinates run down from the top left; the context's run up.
        context.translateBy(x: (size.width - natural.width * fit) / 2, y: (size.height + natural.height * fit) / 2)
        context.scaleBy(x: fit, y: -fit)
        context.setStrokeColor(ink)
        context.setLineWidth(1.5 / Swift.min(1, fit))
        context.setLineJoin(.round)
        scene.shapes.forEach(drawShape)
        scene.paths.forEach(drawPath)
        drawTexts()
        context.restoreGState()
    }

    private func px(_ x: Int32) -> CGFloat { (CGFloat(x) + 0.5) * cell.width }
    private func py(_ y: Int32) -> CGFloat { (CGFloat(y) + 0.5) * cell.height }

    private func drawShape(_ shape: SceneShape) {
        let rect = CGRect(
            x: px(shape.x),
            y: py(shape.y),
            width: CGFloat(shape.width - 1) * cell.width,
            height: CGFloat(shape.height - 1) * cell.height
        )
        switch shape.kind {
            case .diamond:
                context.beginPath()
                context.move(to: CGPoint(x: rect.midX, y: rect.minY))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                context.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                context.closePath()
            case .rounded, .frame: addRounded(rect, radius: 6)
            case .stadium, .circle, .doubleCircle: addRounded(rect, radius: rect.height / 2)
            default: context.addRect(rect)
        }
        context.setFillColor(CGColor(gray: shape.kind == .frame ? 0.97 : 0.94, alpha: 1))
        context.drawPath(using: .fillStroke)
    }

    private func addRounded(_ rect: CGRect, radius: CGFloat) {
        unsafe context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    }

    private func drawPath(_ path: ScenePath) {
        let points = scene.points[Int(path.first) ..< Int(path.first + path.count)]
        guard points.count >= 2, let first = points.first, let last = points.last else { return }
        context.beginPath()
        context.move(to: CGPoint(x: px(first.x), y: py(first.y)))
        for point in points.dropFirst() { context.addLine(to: CGPoint(x: px(point.x), y: py(point.y))) }
        context.strokePath()
        let before = points[points.endIndex - 2]
        let (dx, dy) = (CGFloat((last.x - before.x).signum()), CGFloat((last.y - before.y).signum()))
        let tip = CGPoint(x: px(last.x) + dx * cell.width, y: py(last.y) + dy * cell.height)
        if path.role == .edge {
            context.beginPath()
            context.move(to: CGPoint(x: px(last.x), y: py(last.y)))
            context.addLine(to: tip)
            context.strokePath()
        }
        guard path.endMarker != .none else { return }
        context.beginPath()
        context.move(to: tip)
        context.addLine(to: CGPoint(x: tip.x - dx * 8 - dy * 4, y: tip.y - dy * 8 + dx * 4))
        context.addLine(to: CGPoint(x: tip.x - dx * 8 + dy * 4, y: tip.y - dy * 8 - dx * 4))
        context.closePath()
        context.setFillColor(ink)
        context.fillPath()
    }

    private func drawTexts() {
        for shape in scene.shapes {
            if shape.kind == .frame {
                label(scene.string(shape.text), x: px(shape.x) + 14, baseline: py(shape.y) + 4, centred: false)
                continue
            }
            let lines = scene.string(shape.text).split(separator: "\n", omittingEmptySubsequences: false)
            let middle = py(shape.y) + CGFloat(shape.height - 1) * cell.height / 2
            let first = middle - CGFloat(lines.count - 1) * cell.height / 2 + 4
            let centre = px(shape.x) + CGFloat(shape.width - 1) * cell.width / 2
            for (index, piece) in lines.enumerated() {
                label(String(piece), x: centre, baseline: first + CGFloat(index) * cell.height, centred: true)
            }
        }
        for text in scene.texts {
            let leading = text.anchor == .leading
            label(
                scene.string(text.text),
                x: leading ? Double(text.x) * cell.width : px(Int32(text.x)),
                baseline: py(text.y) + 4,
                centred: !leading
            )
        }
    }

    /// One line of text, upright (the flip of the scene undone around its baseline), centred on `x` or starting at it.
    private func label(_ string: String, x: CGFloat, baseline: CGFloat, centred: Bool) {
        guard !string.isEmpty, let attributed = CFAttributedStringCreateMutable(nil, 0) else { return }
        CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), string as CFString)
        let range = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
        CFAttributedStringSetAttribute(
            attributed,
            range,
            kCTFontAttributeName,
            CTFontCreateUIFontForLanguage(.system, 11, nil)
        )
        CFAttributedStringSetAttribute(attributed, range, kCTForegroundColorAttributeName, CGColor(gray: 0.1, alpha: 1))
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.saveGState()
        context.translateBy(x: centred ? x - width / 2 : x, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
