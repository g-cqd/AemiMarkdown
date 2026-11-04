import AemiMarkdown
import AemiMetrics
import CAemiTestKitMalloc
import Foundation

/// The cost of an edit by size of document and by position (ask roadmap 0203, the position series): CPU time of the thread, instructions and allocations
/// for putting one byte into a paragraph, and taking it out again, at the start, the first block, a quarter, the middle, three quarters, the last block and the end.
/// The documents are the public corpus (Benchmarks/Corpus) joined until they are as large as asked.
///
///     swift run -c release MarkdownBench --edits [--rounds N] [--sizes 23000,103000,1000000,5000000]
func runEditBenchmark(arguments: [String]) -> Int32 {
    func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }
    let rounds = option("--rounds").flatMap(Int.init) ?? 15
    let sizes = (option("--sizes") ?? "23000,103000,1000000,5000000").split(separator: ",").compactMap { Int($0) }
    let cache =
        ProcessInfo.processInfo.environment["AEMI_MARKDOWN_CORPUS"]
        ?? NSString(string: "~/Library/Caches/AemiMarkdownCorpus").expandingTildeInPath
    let directory = cache + "/files"
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory), !names.isEmpty else {
        FileHandle.standardError.write(Data("no corpus in \(cache): run Benchmarks/Corpus/fetch.py setup\n".utf8))
        return 2
    }
    let pieces = names.sorted().compactMap { FileManager.default.contents(atPath: directory + "/" + $0) }
        .filter { $0.count < 400_000 && $0.count > 2_000 }
    var load = [Double](repeating: 0, count: 3)
    getloadavg(&load, 3)
    print(
        "edits: load average \(String(format: "%.1f", load[0])); one byte inserted into a paragraph and taken out, least of \(rounds) rounds"
    )
    print("size        blocks  position          edit CPU µs   instr/edit   allocs/edit   changed blocks   whole")
    for size in sizes {
        var bytes: [UInt8] = []
        var next = 0
        while bytes.count < size {
            bytes.append(contentsOf: pieces[next % pieces.count])
            bytes.append(contentsOf: [10, 10])
            next += 7
        }
        bytes.removeSubrange(size...)
        var editor = MarkdownEditor(bytes)
        let blocks = Array(editor.document.topLevelBlocks)
        let paragraphs = blocks.filter { $0.node.kind == .paragraph && $0.sourceRange.count > 3 }
        guard !paragraphs.isEmpty else { continue }
        func paragraph(near fraction: Double) -> Int {
            let target = Int(Double(bytes.count) * fraction)
            return paragraphs.min { abs($0.sourceRange.lowerBound - target) < abs($1.sourceRange.lowerBound - target) }!
                .sourceRange.lowerBound + 1
        }
        let series: [(String, Int)] = [
            ("start", paragraphs[0].sourceRange.lowerBound + 1), ("quarter", paragraph(near: 0.25)),
            ("middle", paragraph(near: 0.5)),
            ("three quarters", paragraph(near: 0.75)), ("last block", paragraphs.last!.sourceRange.lowerBound + 1)
        ]
        let x: [UInt8] = [UInt8(ascii: "x")]
        for _ in 0 ..< 3 {
            editor.replace(series[2].1 ..< series[2].1, with: x)
            editor.replace(series[2].1 ..< (series[2].1 + 1), with: [])
        }  // warm
        for (name, position) in series {
            var best = Double.infinity
            var bestInstructions = 0.0
            var allocations: UInt64 = 0
            var changed = 0
            var whole = false
            for round in 0 ..< rounds {
                let begin = ProcessProbe.snapshot()
                if round == 0 { adtk_malloc_count_begin() }
                let change = editor.replace(position ..< position, with: x)
                if round == 0 { allocations = adtk_malloc_count_end() }
                let delta = ProcessProbe.delta(from: begin, to: ProcessProbe.snapshot())
                changed = change.insertedBlocks
                whole = editor.lastEditParsedWhole
                if Double(delta.threadCPUNanos) < best {
                    best = Double(delta.threadCPUNanos)
                    bestInstructions = Double(delta.instructions)
                }
                editor.replace(position ..< (position + 1), with: [])
            }
            print(
                String(
                    format: "%-10d %7d  %-15@ %12.1f %12.0f %13d %14d   %@",
                    bytes.count,
                    blocks.count,
                    name as NSString,
                    best / 1e3,
                    bestInstructions,
                    Int(allocations),
                    changed,
                    (whole ? "yes" : "no") as NSString
                )
            )
        }
    }
    return 0
}
