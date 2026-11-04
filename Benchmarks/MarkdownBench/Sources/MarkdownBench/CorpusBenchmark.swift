import AemiMarkdown
import AemiMetrics
import CAemiTestKitMalloc
import Foundation

/// The complete parse of the public corpus, by document size: CPU time of the thread, instructions and cycles (which do not depend on what else the
/// machine is doing), allocations per KB and tape bytes per source byte, one parser reused for document after document.
///
///     swift run -c release MarkdownBench --corpus [--rounds N] [--json results.jsonl] [--max-bytes N]
///
/// The corpus is the cache that `Benchmarks/Corpus/fetch.py setup` fills (`AEMI_MARKDOWN_CORPUS` overrides where it is). An empty cache stops with
/// the reason and exit code 2: a benchmark that ran on nothing would look like a result.
func runCorpusBenchmark(arguments: [String]) -> Int32 {
    func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }
    let rounds = option("--rounds").flatMap(Int.init) ?? 5
    let maxBytes = option("--max-bytes").flatMap(Int.init) ?? Int.max
    let cache =
        ProcessInfo.processInfo.environment["AEMI_MARKDOWN_CORPUS"]
        ?? NSString(string: "~/Library/Caches/AemiMarkdownCorpus").expandingTildeInPath
    let directory = cache + "/files"
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory), !names.isEmpty else {
        FileHandle.standardError.write(Data("no corpus in \(cache): run Benchmarks/Corpus/fetch.py setup\n".utf8))
        return 2
    }
    var documents: [[UInt8]] = []
    for name in names.sorted() {
        if let data = FileManager.default.contents(atPath: directory + "/" + name), data.count <= maxBytes {
            documents.append(Array(data))
        }
    }
    var load = [Double](repeating: 0, count: 3)
    getloadavg(&load, 3)
    print(
        "corpus: \(documents.count) documents, \(documents.reduce(0) { $0 + $1.count }) bytes; load average \(String(format: "%.1f", load[0])); counting available: \(adtk_malloc_counting_available())"
    )

    struct Bin {
        var name: String
        var range: Range<Int>
        var documents: [Int] = []
    }
    var bins = [
        Bin(name: "under 2 KB", range: 0 ..< 2_000), Bin(name: "2 to 5 KB", range: 2_000 ..< 5_000),
        Bin(name: "5 to 20 KB", range: 5_000 ..< 20_000),
        Bin(name: "20 to 100 KB", range: 20_000 ..< 100_000), Bin(name: "100 to 400 KB", range: 100_000 ..< 400_000),
        Bin(name: "400 KB to 2 MB", range: 400_000 ..< 2_000_000),
        Bin(name: "2 MB and over", range: 2_000_000 ..< Int.max)
    ]
    for (index, document) in documents.enumerated() {
        if let bin = bins.firstIndex(where: { $0.range.contains(document.count) }) { bins[bin].documents.append(index) }
    }
    var parser = MarkdownParser()
    for document in documents.prefix(20) {  // warm the parser's buffers and the code
        parser.reset()
        parser.append(document)
        parser.finish()
    }
    var records: [String] = []
    print(
        "bin             docs        bytes   MB/s (CPU)  ns/byte  instr/byte  cycles/byte   per-doc p50 / p95 / max (µs)   allocs/KB   tape B/B"
    )
    for bin in bins where !bin.documents.isEmpty {
        var perDocument: [Double] = []
        var totalNanos = 0.0
        var totalBytes = 0
        var instructions = 0.0
        var cycles = 0.0
        var tape = 0
        var allocationsTotal: UInt64 = 0
        for index in bin.documents {
            let document = documents[index]
            let repeats = document.count > 1_000_000 ? max(2, rounds / 2) : rounds
            var best = Double.infinity
            var bestInstructions = 0.0
            var bestCycles = 0.0
            for _ in 0 ..< repeats {  // the least of the rounds: the run the neighbours disturbed least
                parser.reset()
                let begin = ProcessProbe.snapshot()
                parser.append(document)
                parser.finish()
                let delta = ProcessProbe.delta(from: begin, to: ProcessProbe.snapshot())
                if Double(delta.threadCPUNanos) < best {
                    best = Double(delta.threadCPUNanos)
                    bestInstructions = Double(delta.instructions)
                    bestCycles = Double(delta.cycles)
                }
            }
            perDocument.append(best / 1e3)
            totalNanos += best
            totalBytes += document.count
            instructions += bestInstructions
            cycles += bestCycles
            parser.reset()
            adtk_malloc_count_begin()
            parser.append(document)
            parser.finish()
            allocationsTotal += adtk_malloc_count_end()
            let snapshot = parser.snapshot()
            tape += (snapshot.blockSlotCount + snapshot.inlineSlotCount) * 8
        }
        perDocument.sort()
        let megabytes = Double(totalBytes) / 1e6 / (totalNanos / 1e9)
        let line = String(
            format: "%-14@ %5d %12d %11.1f %8.2f %11.1f %12.1f   %8.1f / %8.1f / %10.1f   %9.2f %9.3f",
            bin.name as NSString,
            bin.documents.count,
            totalBytes,
            megabytes,
            totalNanos / Double(totalBytes),
            instructions / Double(totalBytes),
            cycles / Double(totalBytes),
            perDocument[perDocument.count / 2],
            perDocument[Int(Double(perDocument.count) * 0.95)],
            perDocument.last!,
            Double(allocationsTotal) / (Double(totalBytes) / 1024),
            Double(tape) / Double(totalBytes)
        )
        print(line)
        records.append(
            "{\"tool\":\"MarkdownBench --corpus\",\"bin\":\"\(bin.name)\",\"documents\":\(bin.documents.count),\"bytes\":\(totalBytes),\"mbPerSecondCPU\":\(String(format: "%.2f", megabytes)),\"instructionsPerByte\":\(String(format: "%.2f", instructions / Double(totalBytes))),\"cyclesPerByte\":\(String(format: "%.2f", cycles / Double(totalBytes))),\"p50Microseconds\":\(String(format: "%.1f", perDocument[perDocument.count / 2])),\"allocationsPerKB\":\(String(format: "%.3f", Double(allocationsTotal) / (Double(totalBytes) / 1024))),\"tapeBytesPerSourceByte\":\(String(format: "%.3f", Double(tape) / Double(totalBytes))),\"loadAverage\":\(String(format: "%.1f", load[0]))}"
        )
    }
    print("peak resident bytes of the process: \(ProcessProbe.peakResidentBytes())")
    if let path = option("--json") {
        try? (records.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
    return 0
}
