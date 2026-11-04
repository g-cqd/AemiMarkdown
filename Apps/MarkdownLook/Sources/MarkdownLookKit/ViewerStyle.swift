/// The style sheet of the viewer (ADR 0004, the typography tokens of ask roadmap 0199): the system font at 13 points, a line of 1.6 and a measure of 40 em, generous space between blocks,
/// neutral colour (the only colour is a link's underline and a diagram's), hairlines, light and dark through `prefers-color-scheme`.
public enum ViewerStyle {
    public static let sheet = """
        :root { color-scheme: light dark; --text: #1d1d1f; --secondary: #6e6e73; --tertiary: #a1a1a6; --rule: rgba(0,0,0,0.10); --tint: rgba(0,0,0,0.045); --mark: rgba(0,0,0,0.28);
          --note: #8e8e93; }
        @media (prefers-color-scheme: dark) { :root { --text: #ececf0; --secondary: #98989d; --tertiary: #636366; --rule: rgba(255,255,255,0.13); --tint: rgba(255,255,255,0.07); --mark: rgba(255,255,255,0.35); } }
        html { font: 13px/1.6 -apple-system, system-ui, 'SF Pro Text', sans-serif; font-optical-sizing: auto; -webkit-text-size-adjust: 100%; -webkit-font-smoothing: antialiased; }
        body { margin: 0; padding: 4em 2.5em 6em; background: transparent; color: var(--text); font-kerning: normal; }
        main { max-width: 40em; margin: 0 auto; }
        p { margin: 0 0 1.1em; text-wrap: pretty; }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; margin: 2.2em 0 0.7em; text-wrap: balance; letter-spacing: -0.012em; }
        main > :first-child { margin-top: 0; }
        h1 { font-size: 1.9em; letter-spacing: -0.02em; margin-top: 2.6em; } h2 { font-size: 1.45em; margin-top: 2.4em; } h3 { font-size: 1.15em; } h4 { font-size: 1em; }
        h5, h6 { font-size: 1em; color: var(--secondary); }
        a { color: inherit; text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 0.22em;
          text-decoration-color: color-mix(in srgb, AccentColor 55%, transparent); }
        a:hover { text-decoration-color: AccentColor; }
        strong { font-weight: 600; }
        code, pre { font-family: ui-monospace, 'SF Mono', Menlo, monospace; }
        code { font-size: 0.9em; background: var(--tint); padding: 0.1em 0.3em; border-radius: 0.3em; }
        pre { background: var(--tint); margin: 1.4em 0; padding: 1.1em 1.3em; border-radius: 0.6em; line-height: 1.55; overflow-x: auto; white-space: pre; }
        code[data-n] { white-space: nowrap; }
        pre code { font-size: 0.9em; background: none; padding: 0; border-radius: 0; }
        blockquote { margin: 1.4em 0; padding: 0 0 0 1.4em; border-left: 1px solid var(--mark); color: var(--secondary); }
        blockquote p:last-child { margin-bottom: 0; }
        ul, ol { margin: 0 0 1.1em; padding-left: 1.6em; } li { margin: 0.35em 0; } li > p { margin: 0.5em 0; } ul.tight > li > p, ol.tight > li > p { margin: 0; }
        li > ul, li > ol { margin: 0.35em 0 0; }
        li::marker { color: var(--tertiary); }
        ol { font-variant-numeric: tabular-nums; }
        li:has(> input:first-child), li:has(> p > input:first-child) { list-style: none; margin-left: -1.4em; }
        li input[type=checkbox] { margin: 0 0.6em 0 0; vertical-align: -0.1em; accent-color: var(--secondary); }
        hr { border: 0; border-top: 1px solid var(--rule); margin: 3em 0; }
        .table-wrap { overflow-x: auto; margin: 1.6em 0; -webkit-overflow-scrolling: touch; }
        .table-wrap.wide { margin-inline: calc((100% - min(68em, 100vw - 5em)) / 2); }
        table { border-collapse: collapse; font-variant-numeric: tabular-nums; line-height: 1.45; font-size: 0.96em; }
        th, td { padding: 0.65em 1.4em; border-bottom: 1px solid var(--rule); text-align: left; vertical-align: top; }
        th { font-weight: 500; color: var(--secondary); font-size: 0.92em; border-bottom-color: var(--mark); white-space: nowrap; }
        th:first-child, td:first-child { padding-left: 0; } th:last-child, td:last-child { padding-right: 0; }
        td[data-f], th[data-f] { white-space: nowrap; }
        td p { margin: 0; }
        td code { font-size: 0.88em; }
        .c { text-align: center; } .r { text-align: right; }
        del { color: var(--secondary); }
        figure { margin: 2.2em 0; } figure svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        .image { color: var(--secondary); } .image::before { content: '\\25A3\\00A0'; }
        .alert { margin: 1.6em 0; padding: 0.1em 0 0.1em 1.4em; border-left: 2px solid var(--note); }
        .alert-title { font-weight: 500; font-size: 0.85em; letter-spacing: 0.06em; text-transform: uppercase; color: var(--secondary); margin: 0.6em 0 0.3em; }
        .footnote { color: var(--secondary); font-size: 0.92em; display: flex; gap: 0.7em; margin: 0.5em 0; } .footnote p { margin: 0; } .footnote .label { color: var(--tertiary); min-width: 1.1em; font-variant-numeric: tabular-nums; } sup.fn { font-size: 0.75em; color: var(--secondary); }
        .source { opacity: 0.75; }
        """
}
