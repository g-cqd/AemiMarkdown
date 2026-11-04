internal import AemiMermaidLayout
internal import AemiMermaidSVG
internal import AemiMermaidScene
internal import AemiMermaidSyntax

/// A mermaid fence as SVG (ADR 0007): read within the default limits, laid out in cells, drawn as vector. Nil when the source is not a diagram this engine draws, and the viewer shows it as
/// the code it is.
enum MermaidFence {
    static func svg(_ source: [UInt8], embedsStyle: Bool) -> String? {
        let parse = MermaidParse.parse(source, limits: .default)
        if case .refused = parse.result { return nil }
        if case .pie(let pie) = parse.result {
            var renderer = PieSVG()
            renderer.embedsStyle = embedsStyle
            let markup = renderer.svg(pie)
            return markup.isEmpty ? nil : markup
        }
        var scene = DiagramScene()
        guard case .drawn = MermaidLayout.lay(parse.result, limits: .default, into: &scene) else { return nil }
        var renderer = SVGRenderer()
        renderer.embedsStyle = embedsStyle
        let markup = renderer.svg(scene)
        return markup.isEmpty ? nil : markup
    }
}
