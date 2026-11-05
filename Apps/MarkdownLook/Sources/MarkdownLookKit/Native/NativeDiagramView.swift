internal import AemiMermaidScene
internal import AemiMermaidSyntax
internal import AppKit
import SwiftUI

/// A diagram drawn by SwiftUI's `Canvas` from the scene the layout makes (the same one the SVG and the terminal are drawn from): shapes, orthogonal lines with their markers, the system font,
/// colours of the system so light and dark and the accent follow the window.
struct NativeDiagramView: View {
    let diagram: NativeDiagram
    let size: CGFloat
    @Environment(\.pageFonts) private var fonts

    var body: some View {
        switch diagram {
            case .scene(let scene):
                let natural = CGSize(
                    width: Double(scene.width) * Self.cell.width,
                    height: Double(scene.height) * Self.cell.height
                )
                Canvas { context, canvas in
                    context.scaleBy(x: canvas.width / natural.width, y: canvas.width / natural.width)
                    Self.draw(scene, fonts: fonts, in: &context)
                }
                .aspectRatio(natural.width / Swift.max(1, natural.height), contentMode: .fit)
                .frame(maxWidth: natural.width)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Diagram")
            case .pie(let pie): NativePieView(pie: pie, size: size)
        }
    }

    static let cell = CGSize(width: 9, height: 18)
    private static func px(_ x: Int32) -> CGFloat { (CGFloat(x) + 0.5) * cell.width }
    private static func py(_ y: Int32) -> CGFloat { (CGFloat(y) + 0.5) * cell.height }

    static func draw(_ scene: DiagramScene, fonts: NativeFonts, in context: inout GraphicsContext) {
        let line = 1.5
        let stroke = NativeTheme.secondary
        for shape in scene.shapes { drawShape(shape, scene, fonts, &context, line: line, stroke: stroke) }
        for path in scene.paths { drawPath(path, scene, &context, line: line, stroke: stroke) }
        for text in scene.texts {
            let x = text.anchor == .center ? px(Int32(text.x)) : CGFloat(text.x) * cell.width
            let muted = text.role == .label || text.role == .clusterTitle
            setText(
                scene.string(text.text),
                at: CGPoint(x: x, y: py(Int32(text.y)) + 4.5),
                anchor: text.anchor,
                size: text.role == .label ? 13 * 0.92 : 13,
                weight: text.role == .clusterTitle ? .medium : .regular,
                color: muted ? NativeTheme.pieMuted : NativeTheme.text,
                fonts: fonts,
                in: &context
            )
        }
    }

    /// A line of text on a baseline, at 13 points, as the page's SVG sets it.
    static func setText(
        _ string: String,
        at point: CGPoint,
        anchor: SceneAnchor,
        size: CGFloat = 13,
        weight: Font.Weight = .regular,
        color: Color,
        fonts: NativeFonts,
        in context: inout GraphicsContext
    ) {
        let resolved = context.resolve(
            Text(string).font(fonts.font(.diagram, size: size, weight: weight)).foregroundColor(color)
        )
        let box = resolved.measure(in: CGSize(width: 10_000, height: 10_000))
        let x = point.x
        let baseline = point.y
        let left = anchor == .leading ? x : (anchor == .center ? x - box.width / 2 : x - box.width)
        context.draw(resolved, at: CGPoint(x: left, y: baseline - resolved.firstBaseline(in: box)), anchor: .topLeading)
    }

    /// The outline of a shape's box in the cell grid: where a line meets it is the middle of its edge cells.
    private static func outline(_ kind: SceneShapeKind, in rect: CGRect) -> Path {
        let slant = Swift.min(12, rect.width / 4)
        let (minX, midX, maxX, minY, midY, maxY) = (rect.minX, rect.midX, rect.maxX, rect.minY, rect.midY, rect.maxY)
        var path = Path()
        switch kind {
            case .rectangle, .actor, .bar, .subroutine: path.addRect(rect)
            case .rounded, .frame: path.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
            case .cylinder: path.addRoundedRect(in: rect, cornerSize: CGSize(width: 6, height: 6))
            case .stadium, .circle, .doubleCircle:
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))
            case .diamond:
                path.addLines([
                    CGPoint(x: midX, y: minY), CGPoint(x: maxX, y: midY), CGPoint(x: midX, y: maxY),
                    CGPoint(x: minX, y: midY), CGPoint(x: midX, y: minY)
                ])
            case .hexagon:
                path.addLines([
                    CGPoint(x: minX + slant, y: minY), CGPoint(x: maxX - slant, y: minY), CGPoint(x: maxX, y: midY),
                    CGPoint(x: maxX - slant, y: maxY),
                    CGPoint(x: minX + slant, y: maxY), CGPoint(x: minX, y: midY), CGPoint(x: minX + slant, y: minY)
                ])
            case .parallelogram:
                path.addLines([
                    CGPoint(x: minX + slant, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX - slant, y: maxY),
                    CGPoint(x: minX, y: maxY), CGPoint(x: minX + slant, y: minY)
                ])
            case .parallelogramAlt:
                path.addLines([
                    CGPoint(x: minX, y: minY), CGPoint(x: maxX - slant, y: minY), CGPoint(x: maxX, y: maxY),
                    CGPoint(x: minX + slant, y: maxY), CGPoint(x: minX, y: minY)
                ])
            case .trapezoid:
                path.addLines([
                    CGPoint(x: minX + slant, y: minY), CGPoint(x: maxX - slant, y: minY), CGPoint(x: maxX, y: maxY),
                    CGPoint(x: minX, y: maxY), CGPoint(x: minX + slant, y: minY)
                ])
            case .trapezoidAlt:
                path.addLines([
                    CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX - slant, y: maxY),
                    CGPoint(x: minX + slant, y: maxY), CGPoint(x: minX, y: minY)
                ])
            case .asymmetric:
                path.addLines([
                    CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY),
                    CGPoint(x: minX, y: maxY), CGPoint(x: minX + slant, y: midY), CGPoint(x: minX, y: minY)
                ])
            case .note:
                path.addLines([
                    CGPoint(x: minX, y: minY), CGPoint(x: maxX - 9, y: minY), CGPoint(x: maxX, y: minY + 9),
                    CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY), CGPoint(x: minX, y: minY)
                ])
        }
        return path
    }

    /// The lines inside a shape's outline that make it a double circle, a subroutine or a cylinder.
    private static func inner(_ kind: SceneShapeKind, in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
            case .doubleCircle:
                path.addRoundedRect(
                    in: rect.insetBy(dx: 3, dy: 3),
                    cornerSize: CGSize(width: rect.height / 2 - 3, height: rect.height / 2 - 3)
                )
            case .subroutine:
                path.move(to: CGPoint(x: rect.minX + 9, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + 9, y: rect.maxY))
                path.move(to: CGPoint(x: rect.maxX - 9, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - 9, y: rect.maxY))
            case .cylinder:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + 9))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 9))
            default: break
        }
        return path
    }

    private static func drawShape(
        _ shape: SceneShape,
        _ scene: DiagramScene,
        _ fonts: NativeFonts,
        _ context: inout GraphicsContext,
        line: CGFloat,
        stroke: Color
    ) {
        let left = px(shape.x)
        let top = py(shape.y)
        let rect = CGRect(
            x: left,
            y: top,
            width: px(shape.x + shape.width - 1) - left,
            height: py(shape.y + shape.height - 1) - top
        )
        let path = outline(shape.kind, in: rect)
        if shape.kind == .frame {
            context.stroke(
                path,
                with: .color(NativeTheme.pieMuted.opacity(0.8)),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round, dash: [4, 3])
            )
        } else {
            context.fill(path, with: .color(shape.kind == .note ? NativeTheme.surface : NativeTheme.diagramFill))
            context.stroke(
                path,
                with: .color(shape.kind == .note ? NativeTheme.pieMuted : stroke),
                style: StrokeStyle(lineWidth: line, lineJoin: .round)
            )
        }
        context.stroke(
            inner(shape.kind, in: rect),
            with: .color(stroke),
            style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        )
        let words = scene.string(shape.text)
        guard !words.isEmpty else { return }
        if shape.kind == .frame {
            setText(
                words,
                at: CGPoint(x: rect.minX + 14, y: rect.minY + 4.5),
                anchor: .leading,
                weight: .medium,
                color: NativeTheme.pieMuted,
                fonts: fonts,
                in: &context
            )
            return
        }
        let lines = words.split(separator: "\n", omittingEmptySubsequences: false)
        let first = rect.midY - CGFloat(lines.count - 1) * cell.height / 2 + 4.5
        for (index, piece) in lines.enumerated() {
            setText(
                String(piece),
                at: CGPoint(x: rect.midX, y: first + CGFloat(index) * cell.height),
                anchor: .center,
                color: NativeTheme.text,
                fonts: fonts,
                in: &context
            )
        }
    }

    private static func drawPath(
        _ path: ScenePath,
        _ scene: DiagramScene,
        _ context: inout GraphicsContext,
        line: CGFloat,
        stroke: Color
    ) {
        let points = Array(scene.points[Int(path.first) ..< Int(path.first + path.count)])
        guard points.count >= 2 else { return }
        var coordinates = points.map { CGPoint(x: px($0.x), y: py($0.y)) }
        let last = points[points.count - 1]
        let before = points[points.count - 2]
        let heading = (dx: CGFloat((last.x - before.x).signum()), dy: CGFloat((last.y - before.y).signum()))
        let tip = CGPoint(
            x: coordinates[coordinates.count - 1].x + heading.dx * cell.width,
            y: coordinates[coordinates.count - 1].y + heading.dy * cell.height
        )
        // An edge runs on to the border of the shape its last cell touches, with a marker or without.
        if path.endMarker != .none || path.role == .edge { coordinates.append(tip) }
        var drawn = Path()
        drawn.addLines(coordinates)
        var style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        var color = stroke
        switch (path.role, path.stroke) {
            case (.activation, _):
                style.lineWidth = 5
                color = stroke.opacity(0.45)
            case (.muted, _):
                style.dash = [0.1, 5]
                color = NativeTheme.pieMuted.opacity(0.8)
            case (.cluster, _):
                style.dash = [4, 3]
                color = NativeTheme.pieMuted.opacity(0.8)
            case (_, .dashed): style.dash = [5, 4]
            case (_, .thick): style.lineWidth = 3
            default: break
        }
        context.stroke(drawn, with: .color(color), style: style)
        marker(path.endMarker, at: tip, heading: heading, in: &context, stroke: stroke, line: line)
        let outward = (
            dx: CGFloat((points[0].x - points[1].x).signum()), dy: CGFloat((points[0].y - points[1].y).signum())
        )
        marker(path.startMarker, at: coordinates[0], heading: outward, in: &context, stroke: stroke, line: line)
    }

    private static func marker(
        _ kind: SceneMarker,
        at tip: CGPoint,
        heading: (dx: CGFloat, dy: CGFloat),
        in context: inout GraphicsContext,
        stroke: Color,
        line: CGFloat
    ) {
        let (nx, ny) = (-heading.dy, heading.dx)
        let (bx, by) = (tip.x - heading.dx * 8, tip.y - heading.dy * 8)
        var path = Path()
        switch kind {
            case .none: return
            case .arrow:
                path.addLines([
                    tip, CGPoint(x: bx + nx * 4, y: by + ny * 4), CGPoint(x: bx - nx * 4, y: by - ny * 4), tip
                ])
                context.fill(path, with: .color(stroke))
                context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: line, lineJoin: .round))
            case .async:
                path.addLines([CGPoint(x: bx + nx * 4, y: by + ny * 4), tip, CGPoint(x: bx - nx * 4, y: by - ny * 4)])
                context.stroke(
                    path,
                    with: .color(stroke),
                    style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
                )
            case .circle:
                path.addEllipse(
                    in: CGRect(x: tip.x - heading.dx * 5 - 4.5, y: tip.y - heading.dy * 5 - 4.5, width: 9, height: 9)
                )
                context.fill(path, with: .color(NativeTheme.diagramFill))
                context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: line))
            case .cross:
                let (cx, cy) = (tip.x - heading.dx * 5, tip.y - heading.dy * 5)
                path.move(to: CGPoint(x: cx - 4, y: cy - 4))
                path.addLine(to: CGPoint(x: cx + 4, y: cy + 4))
                path.move(to: CGPoint(x: cx - 4, y: cy + 4))
                path.addLine(to: CGPoint(x: cx + 4, y: cy - 4))
                context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: line, lineCap: .round))
        }
    }
}

/// A pie chart drawn on the page's own geometry (`PieSVG`): a circle of radius 90 with the legend 40 to the right of it, the title centred over the whole at the top, 13 point text, the figure at its
/// natural size and no wider than its column.
struct NativePieView: View {
    let pie: PieDiagram
    let size: CGFloat
    @Environment(\.pageFonts) private var fonts

    private let radius = 90.0

    private var labels: [String] { pie.slices.map { String(decoding: pie.labels.slice($0.label), as: UTF8.self) } }
    private var width: Double { radius * 2 + 40 + Double((labels.map(\.count).max() ?? 0) * 8 + 90) }
    private var top: Double { pie.title == nil ? 20 : 44 }
    private var height: Double { Swift.max(radius * 2 + top + 20, Double(pie.slices.count) * 20 + top + 20) }

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / width
            context.scaleBy(x: scale, y: scale)
            draw(&context)
        }
        .aspectRatio(width / height, contentMode: .fit)
        .frame(maxWidth: width)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Pie chart")
    }

    private func draw(_ context: inout GraphicsContext) {
        let total = pie.slices.reduce(0) { $0 + $1.value }
        let centre = CGPoint(x: radius + 20, y: top + radius)
        if let title = pie.title {
            let text = String(decoding: pie.labels.slice(title), as: UTF8.self)
            baseline(
                text,
                at: CGPoint(x: width / 2, y: 24),
                weight: .medium,
                color: NativeTheme.pieMuted,
                centered: true,
                in: &context
            )
        }
        var angle = Angle.degrees(-90)
        for (index, slice) in pie.slices.enumerated() {
            let sweep = Angle.degrees(slice.value / total * 360)
            var path = Path()
            if pie.slices.count == 1 {
                path.addEllipse(
                    in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
                )
            } else {
                path.move(to: centre)
                path.addArc(
                    center: centre,
                    radius: radius,
                    startAngle: angle,
                    endAngle: angle + sweep,
                    clockwise: false
                )
                path.closeSubpath()
            }
            context.fill(path, with: .color(NativeTheme.pie(index)))
            if pie.slices.count > 1 {
                context.stroke(
                    path,
                    with: .color(Color(nsColor: .windowBackgroundColor)),
                    style: StrokeStyle(lineWidth: 1.5, lineJoin: .miter)
                )
            }
            angle += sweep
            let legend = CGPoint(x: radius * 2 + 40, y: top + 4 + Double(index) * 20)
            context.fill(
                Path(roundedRect: CGRect(x: legend.x, y: legend.y, width: 12, height: 12), cornerRadius: 2),
                with: .color(NativeTheme.pie(index))
            )
            baseline(
                caption(index, slice, total),
                at: CGPoint(x: legend.x + 18, y: legend.y + 10.5),
                weight: .regular,
                color: NativeTheme.text,
                centered: false,
                in: &context
            )
        }
    }

    /// Text set on a baseline, as an SVG text is.
    private func baseline(
        _ string: String,
        at point: CGPoint,
        weight: Font.Weight,
        color: Color,
        centered: Bool,
        in context: inout GraphicsContext
    ) {
        let resolved = context.resolve(
            Text(string).font(fonts.font(.diagram, size: 13, weight: weight)).foregroundColor(color)
        )
        let box = resolved.measure(in: CGSize(width: 10_000, height: 10_000))
        let origin = CGPoint(
            x: centered ? point.x - box.width / 2 : point.x,
            y: point.y - resolved.firstBaseline(in: box)
        )
        context.draw(resolved, at: origin, anchor: .topLeading)
    }

    private func caption(_ index: Int, _ slice: PieDiagram.Slice, _ total: Double) -> String {
        let share = Int((slice.value / total * 1000).rounded())
        var text = labels[index] + " \(share / 10).\(share % 10)%"
        if pie.showData { text += " (\(slice.value.formatted()))" }
        return text
    }
}
