/// The style sheet of the viewer (ADR 0004, the typography tokens of ask roadmap 0199): the system font at 13 points, a line of 1.6 and a measure of 40 em, generous space between blocks,
/// neutral colour (the only colour is a link's underline and a diagram's), hairlines, light and dark through `prefers-color-scheme`.
public enum ViewerStyle {
    public static let sheet = """
        :root { color-scheme: light dark; --text: #1d1d1f; --secondary: #6e6e73; --tertiary: #a1a1a6; --rule: rgba(0,0,0,0.10); --tint: rgba(0,0,0,0.045); --mark: rgba(0,0,0,0.28);
          --note: #8e8e93; --indent: 1.75em; --link: #0a64d6;
          --k: #9b2393; --s: #c2371f; --c: #7a8089; --n: #1c5fd1; --t: #1f6f7a; --a: #8a5a14; --g: #9b2393; --p: #3a6ea5; --e: #b0511f; }
        @media (prefers-color-scheme: dark) { :root { --text: #ececf0; --secondary: #98989d; --tertiary: #636366; --rule: rgba(255,255,255,0.13); --tint: rgba(255,255,255,0.07); --mark: rgba(255,255,255,0.35); --link: #4da3ff;
          --k: #ff7ab2; --s: #ff8f7a; --c: #7d8590; --n: #d9c97c; --t: #6bd4e8; --a: #e0b36a; --g: #ff7ab2; --p: #8ab6f0; --e: #ffb085; } }
        /* Rhythm. One scale, used by everything: space goes only above a sibling (so a first child has none and nothing collapses), in these steps.
           gap: between blocks of prose. gap-s: between items and inside a group. gap-box: around code, figures, tables, quotes. gap-sect: before a heading, a rule, the notes.
           gap-head: under a heading. indent: every nesting level, for lists, quotes, alerts. pad: inside a box. cell: inside a table cell. */
        :root { --gap: 1em; --gap-s: 0.4em; --gap-box: 1.5em; --gap-sect: 2.2em; --gap-head: 0.6em; --pad: 1.1em 1.3em; --cell: 0.6em 1.4em; --radius: 0.6em; --radius-s: 0.3em;
          --stroke: 1.5px; --leading: 1.6em; --hair: var(--stroke); --bar: var(--stroke); --page: 3.5em 2.5em 5em; --measure: 40em; }
        html { font: 13px/1.6 -apple-system, system-ui, 'SF Pro Text', sans-serif; font-optical-sizing: auto; -webkit-text-size-adjust: 100%; -webkit-font-smoothing: antialiased; }
        body { margin: 0; padding: var(--page); background: transparent; color: var(--text); font-kerning: normal; }
        main { max-width: var(--measure); margin: 0 auto; }
        :where(p, ul, ol, pre, blockquote, figure, hr, h1, h2, h3, h4, h5, h6) { margin: 0; }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; text-wrap: balance; letter-spacing: -0.012em; }
        h1 { font-size: 1.9em; letter-spacing: -0.02em; } h2 { font-size: 1.45em; } h3 { font-size: 1.15em; } h4 { font-size: 1em; }
        h5, h6 { font-size: 1em; color: var(--secondary); }
        :where(main, blockquote, .alert, li) > :where(* + *) { margin-block-start: var(--gap); }
        * + :is(pre, .code, figure, .table-wrap, blockquote, .alert), :is(pre, .code, figure, .table-wrap, blockquote, .alert) + * { margin-block-start: var(--gap-box); }
        * + :is(hr, .footnotes), hr + *, .footnotes + * { margin-block-start: var(--gap-sect); }
        :is(h1, h2, h3, h4, h5, h6) + * { margin-block-start: var(--gap-head); }
        :where(main, blockquote, .alert, li) > * + :is(h1, h2, h3, h4, h5, h6) { margin-block-start: var(--gap-sect); }
        /* A selection paints out to the edge of the box that holds the text, so prose boxes are as wide as their text (and no wider than the column): the highlight follows the words. */
        :is(p, h1, h2, h3, h4, h5, h6, li, .alert-title, .footnote p) { width: fit-content; max-width: 100%; }
        ::selection { background: color-mix(in srgb, var(--link) 28%, transparent); }
        a { color: var(--link); text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 0.22em;
          text-decoration-color: color-mix(in srgb, var(--link) 35%, transparent); }
        a:hover { text-decoration-color: var(--link); }
        strong { font-weight: 600; }
        code, pre { font-family: ui-monospace, 'SF Mono', Menlo, monospace; }
        code { font-size: 0.9em; background: var(--tint); padding: 0.1em 0.3em; border-radius: var(--radius-s); }
        code[data-n] { white-space: nowrap; }
        pre { background: var(--tint); padding: var(--pad); border-radius: var(--radius); line-height: 1.55; overflow-x: auto; white-space: pre; }
        pre code { font-size: 0.9em; background: none; padding: 0; border-radius: 0; }
        .code { position: relative; } .code > pre { margin: 0; }
        .lang { position: absolute; top: 0.55em; right: 0.9em; font: 500 0.75em/1 -apple-system, system-ui, sans-serif; letter-spacing: 0.04em; color: var(--tertiary); user-select: none; -webkit-user-select: none; pointer-events: none; }
        pre code .k { color: var(--k); } pre code .s { color: var(--s); } pre code .e { color: var(--e); } pre code .n { color: var(--n); } pre code .t { color: var(--t); }
        pre code .a { color: var(--a); } pre code .g { color: var(--g); } pre code .p { color: var(--p); } pre code .c { color: var(--c); font-style: italic; text-align: inherit; }
        blockquote, .alert { position: relative; padding-left: var(--indent); }
        blockquote::before, .alert::before { content: ''; position: absolute; left: 0; top: 0; bottom: 0; width: var(--bar); border-radius: 1px; background: var(--mark); }
        blockquote { color: var(--secondary); } .alert::before { background: var(--note); }
        .alert-title { font-weight: 500; font-size: 0.85em; letter-spacing: 0.06em; text-transform: uppercase; color: var(--secondary); }
        .alert > .alert-title + * { margin-block-start: var(--gap-s); }
        ul, ol { padding-left: var(--indent); --item: var(--gap); } ul.tight, ol.tight { --item: var(--gap-s); } ol { font-variant-numeric: tabular-nums; }
        /* Items of a list are --item apart (tight or loose), and a list inside an item starts the same distance below its parent's text, so a child never sits farther from its parent than the next item does. */
        li { position: relative; --above: var(--item); } li + li { margin-block-start: var(--item); }
        li > :is(ul, ol) { margin-block-start: var(--above); }
        :is(ul, ol).tight > li > :where(* + *) { margin-block-start: var(--gap-s); }
        li::marker { color: var(--tertiary); }
        li:has(> input:first-child), li:has(> p > input:first-child) { list-style: none; }
        /* A checkbox is drawn here, not by the system (which ignores its size): a box of 1em, centred on the first line of its item, so it follows the text at every size. */
        li input[type=checkbox] { -webkit-appearance: none; appearance: none; font: inherit; position: absolute; left: calc(-1 * var(--indent)); top: calc((var(--leading) - 0.95em) / 2); width: 0.95em; height: 0.95em;
          margin: 0; box-sizing: border-box; border: var(--stroke) solid var(--tertiary); border-radius: 0.28em; background: transparent center / 72% no-repeat; }
        li input[type=checkbox]:checked { border-color: var(--secondary); background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 247 243'%3E%3Cpath d='M98 230c6 0 11-3 15-8L230 39c3-4 4-8 4-11 0-9-6-15-15-15-6 0-10 2-14 8L97 194 41 122c-4-5-8-7-13-7-9 0-15 6-15 15 0 4 1 8 5 11l65 81c4 5 9 8 15 8z' fill='%236e6e73'/%3E%3C/svg%3E"); }
        @media (prefers-color-scheme: dark) { li input[type=checkbox]:checked { background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 247 243'%3E%3Cpath d='M98 230c6 0 11-3 15-8L230 39c3-4 4-8 4-11 0-9-6-15-15-15-6 0-10 2-14 8L97 194 41 122c-4-5-8-7-13-7-9 0-15 6-15 15 0 4 1 8 5 11l65 81c4 5 9 8 15 8z' fill='%2398989d'/%3E%3C/svg%3E"); } }
        hr { border: 0; height: var(--hair); border-radius: 1px; background: var(--rule); }
        .table-wrap { overflow-x: auto; -webkit-overflow-scrolling: touch; }
        .table-wrap { scrollbar-width: none; } .table-wrap::-webkit-scrollbar { display: none; }
        .table-wrap.wide { margin-inline: calc((100% - min(68em, 100vw - 5em)) / 2); }
        .table-wrap.wide table { margin-inline: auto; }
        table { border-collapse: collapse; font-variant-numeric: tabular-nums; line-height: 1.45; font-size: 0.96em; }
        /* A document's head, on the text's own grid: no box, no rules. One line closed (its title, its format, how many), the chevron
           hanging in the margin as a list's marker does; open, a line a property, keys and values at the text's size and leading, the
           keys at the column's edge (indented a level a nesting), the values on one column, a list of words as words. */
        .front-matter > summary { list-style: none; position: relative; display: flex; align-items: baseline; gap: 0.6em; line-height: var(--leading);
          color: var(--tertiary); cursor: default; }
        .front-matter > summary::-webkit-details-marker { display: none; }
        .front-matter > summary::before { content: '\\203A'; position: absolute; left: -1.1em; width: 0.6em; text-align: center; transition: transform 0.15s; }
        .front-matter[open] > summary::before { transform: rotate(90deg); }
        .fm-title { min-width: 0; color: var(--text); font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .fm-kind, .fm-count { white-space: nowrap; } .fm-count { margin-inline-start: auto; }
        table.fm { width: 100%; font-size: 1em; line-height: var(--leading); }
        table.fm th, table.fm td { padding: 0; vertical-align: baseline; text-align: left; }
        table.fm th { width: 1%; white-space: nowrap; font-weight: 400; color: var(--secondary); padding-inline-end: 1.5em; }
        table.fm td { overflow-wrap: anywhere; white-space: pre-line; }
        .fm-tags > span + span::before { content: '\\202F\\00B7\\2009'; color: var(--tertiary); }
        table.fm :is(th, td)::after { content: none; } table.fm th { font-size: 1em; }
        th, td { position: relative; padding: var(--cell); text-align: left; vertical-align: top; }
        th::after, td::after { content: ''; position: absolute; left: 0; right: 0; bottom: 0; height: var(--hair); background: var(--rule); }
        th:first-child::after, td:first-child::after { border-radius: 1px 0 0 1px; } th:last-child::after, td:last-child::after { border-radius: 0 1px 1px 0; }
        th { font-weight: 500; color: var(--secondary); font-size: 0.92em; white-space: nowrap; } th::after { background: var(--mark); }
        th:first-child, td:first-child { padding-left: 0; } th:last-child, td:last-child { padding-right: 0; }
        td[data-f], th[data-f] { white-space: nowrap; } td code { font-size: 0.88em; }
        .c { text-align: center; } .r { text-align: right; }
        del { color: var(--secondary); }
        figure svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        .image { color: var(--secondary); } .image::before { content: '\\25A3\\00A0'; }
        .footnotes { position: relative; padding-top: var(--gap-box); display: grid; grid-template-columns: max-content 1fr auto; column-gap: 0.7em; row-gap: var(--gap-s); color: var(--secondary); font-size: 0.92em; }
        .footnotes::before { content: ''; position: absolute; top: 0; left: 0; width: 5em; height: var(--hair); border-radius: 1px; background: var(--mark); }
        .footnotes > .footnote { display: grid; grid-column: 1 / -1; grid-template-columns: subgrid; align-items: baseline; margin: 0; }
        .footnote p { margin: 0; } .footnote .label { color: var(--tertiary); font-variant-numeric: tabular-nums; }
        .footnote .back { color: var(--tertiary); text-decoration: none; } .footnote .back:hover { color: var(--link); }
        sup.fn { font-size: 0.75em; line-height: 0; } sup.fn a { text-decoration: none; color: var(--link); padding: 0 0.1em; }
        :target { background: var(--tint); border-radius: var(--radius-s); }
        .source { opacity: 0.75; }
        """
}
