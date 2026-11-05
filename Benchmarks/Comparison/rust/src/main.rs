// The Rust engines of the comparison (Benchmarks/Comparison): pulldown-cmark and comrak, Markdown to HTML on one thread, the best round's CPU time.
// usage: compare-rust DIR [--rounds N] [--engine NAME]
use std::{env, fs};

fn cpu() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 / 1e9
}

fn measure(name: &str, version: &str, docs: &[String], rounds: usize, only: &Option<String>, f: &dyn Fn(&str) -> usize) {
    if let Some(o) = only { if o != name { return; } }
    let total: usize = docs.iter().map(|d| d.len()).sum();
    let mut out = 0;
    for d in docs { out += f(d); }
    let mut best = f64::INFINITY;
    for _ in 0..rounds {
        let start = cpu();
        let mut produced = 0;
        for d in docs { produced += f(d); }
        best = best.min(cpu() - start);
        out = produced;
    }
    println!("{{\"engine\":\"{}\",\"version\":\"{}\",\"what\":\"html\",\"documents\":{},\"bytes\":{},\"seconds\":{},\"mbps\":{},\"output_bytes\":{}}}",
        name, version, docs.len(), total, best, total as f64 / best / 1e6, out);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let dir = &args[1];
    let opt = |n: &str| args.iter().position(|a| a == n).and_then(|i| args.get(i + 1)).cloned();
    let rounds = opt("--rounds").and_then(|r| r.parse().ok()).unwrap_or(5);
    let only = opt("--engine");
    let mut names: Vec<_> = fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).collect();
    names.sort();
    let docs: Vec<String> = names.iter().filter_map(|p| fs::read(p).ok()).map(|b| String::from_utf8_lossy(&b).into_owned()).collect();
    measure("pulldown-cmark", "0.13", &docs, rounds, &only, &|d| {
        let mut out = String::new();
        pulldown_cmark::html::push_html(&mut out, pulldown_cmark::Parser::new_ext(d, pulldown_cmark::Options::ENABLE_TABLES | pulldown_cmark::Options::ENABLE_FOOTNOTES | pulldown_cmark::Options::ENABLE_STRIKETHROUGH | pulldown_cmark::Options::ENABLE_TASKLISTS));
        out.len()
    });
    let mut options = comrak::Options::default();
    options.extension.table = true;
    options.extension.strikethrough = true;
    options.extension.tasklist = true;
    options.extension.footnotes = true;
    measure("comrak", "0.40", &docs, rounds, &only, &|d| comrak::markdown_to_html(d, &options).len());
}
