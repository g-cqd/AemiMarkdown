// The JavaScript engines of the comparison (Benchmarks/Comparison): markdown-it, marked and commonmark.js, Markdown to HTML, the best round's CPU time of the process.
// usage: node bench.mjs DIR [--rounds N] [--engine NAME]
import fs from "node:fs";
import { createRequire } from "node:module";
import MarkdownIt from "markdown-it";
import { marked } from "marked";
import * as commonmark from "commonmark";
const require = createRequire(import.meta.url);
const args = process.argv.slice(2);
const dir = args[0];
const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const rounds = Number(opt("--rounds") ?? 5);
const only = opt("--engine");
const docs = fs.readdirSync(dir).sort().map((n) => fs.readFileSync(`${dir}/${n}`, "utf8"));
const total = docs.reduce((s, d) => s + Buffer.byteLength(d), 0);
const cpu = () => { const u = process.cpuUsage(); return (u.user + u.system) / 1e6; };
function measure(name, version, convert) {
  if (only && only !== name) return;
  let out = 0;
  for (const d of docs) out += convert(d).length;
  let best = Infinity;
  for (let r = 0; r < rounds; r++) {
    const start = cpu(); let produced = 0;
    for (const d of docs) produced += convert(d).length;
    best = Math.min(best, cpu() - start); out = produced;
  }
  console.log(JSON.stringify({ engine: name, version, what: "html", documents: docs.length, bytes: total, seconds: best, mbps: total / best / 1e6, output_bytes: out }));
}
const md = new MarkdownIt({ html: true });
measure("markdown-it", require("markdown-it/package.json").version, (d) => md.render(d));
measure("marked", require("marked/package.json").version, (d) => marked.parse(d));
const reader = new commonmark.Parser(); const writer = new commonmark.HtmlRenderer();
measure("commonmark.js", JSON.parse(fs.readFileSync(new URL("./node_modules/commonmark/package.json", import.meta.url))).version, (d) => writer.render(reader.parse(d)));
