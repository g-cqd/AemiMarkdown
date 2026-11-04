/// The style sheet of the viewer (ADR 0007, the typography tokens of ask roadmap 0199): the system font at 13 points, a measure of about 32 em, a line of 1.4 for prose, hairlines,
/// tinted code, light and dark through `prefers-color-scheme` and the system colours.
public enum ViewerStyle {
    public static let sheet = """
        :root { color-scheme: light dark; --text: #1d1d1f; --secondary: #6e6e73; --surface: #f5f5f7; --rule: rgba(0,0,0,0.14); --link: #0066cc; --tint: rgba(0,0,0,0.06);
          --note: #0a84ff; --tip: #30d158; --important: #bf5af2; --warning: #ff9f0a; --caution: #ff453a; }
        @media (prefers-color-scheme: dark) { :root { --text: #f5f5f7; --secondary: #98989d; --surface: #1c1c1e; --rule: rgba(255,255,255,0.18); --link: #64d2ff; --tint: rgba(255,255,255,0.09); } }
        html { font: 13px/1.4 -apple-system, system-ui, 'SF Pro Text', sans-serif; font-optical-sizing: auto; -webkit-text-size-adjust: 100%; }
        body { margin: 0; padding: 2em; background: transparent; color: var(--text); font-kerning: normal; hanging-punctuation: first; }
        main { max-width: 42em; margin: 0 auto; }
        p { margin: 0.6em 0; text-wrap: pretty; }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.2; margin: 1.25em 0 0.5em; text-wrap: balance; }
        h1 { font-size: 2em; margin-top: 2em; } h2 { font-size: 1.69em; margin-top: 1.5em; } h3 { font-size: 1.31em; } h4 { font-size: 1.15em; }
        h5, h6 { font-size: 1em; line-height: 1.4; } h6 { color: var(--secondary); }
        a { color: var(--link); text-decoration: underline; text-underline-offset: 0.15em; }
        code, pre { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 1em; }
        code { background: var(--tint); padding: 0 0.2em; border-radius: 0.25em; }
        pre { background: var(--tint); margin: 0.75em 0; padding: 0.75em 1em; border-radius: 0.4em; line-height: 1.35; overflow-x: auto; white-space: pre; }
        pre code { background: none; padding: 0; border-radius: 0; }
        blockquote { margin: 0.6em 0; padding: 0 0 0 1em; border-left: 2px solid var(--rule); }
        ul, ol { margin: 0.6em 0; padding-left: 1.5em; } li { margin: 0.2em 0; } li > p { margin: 0.3em 0; } ul.tight > li > p, ol.tight > li > p { margin: 0; }
        ol { font-variant-numeric: tabular-nums; } li:has(> input:first-child), li:has(> p > input:first-child) { list-style: none; margin-left: -1.3em; } li input[type=checkbox] { margin: 0 0.5em 0 0; vertical-align: -0.1em; }
        hr { border: 0; border-top: 1px solid var(--rule); margin: 1.4em 0; }
        table { border-collapse: collapse; margin: 0.75em 0; font-variant-numeric: tabular-nums; line-height: 1.3; }
        th, td { padding: 0.35em 0.5em; border-bottom: 1px solid var(--rule); text-align: left; } th { font-weight: 600; } .c { text-align: center; } .r { text-align: right; }
        del { color: var(--secondary); }
        figure { margin: 1.4em 0; } figure svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        .image { color: var(--secondary); } .image::before { content: '\\25A3\\00A0'; }
        .alert { margin: 0.8em 0; padding: 0.1em 1em; border-left: 3px solid var(--note); background: var(--tint); border-radius: 0 0.4em 0.4em 0; }
        .alert-title { font-weight: 600; margin: 0.5em 0 0.2em; } .alert.tip { border-color: var(--tip); } .alert.important { border-color: var(--important); }
        .alert.warning { border-color: var(--warning); } .alert.caution { border-color: var(--caution); }
        .footnote { color: var(--secondary); font-size: 0.92em; } sup.fn { font-size: 0.75em; color: var(--link); }
        .source { opacity: 0.75; }
        """
}
