import AemiMarkdown
import CAemiTestKitMalloc
import Foundation

// One {"t": "<assistant message>"} per line. The corpus is private (session logs) and is never committed.
// CPU time of this thread, not wall time: the machine is shared, and a wall clock measures the neighbours too.
func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }
func percentile(_ sorted: [Double], _ p: Double) -> Double {
    sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
}

guard CommandLine.arguments.count > 1, let data = FileManager.default.contents(atPath: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: MarkdownBench corpus.ndjson\n".utf8))
    exit(2)
}
var messages: [[UInt8]] = []
for line in data.split(separator: UInt8(ascii: "\n")) {
    if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: String], let text = object["t"] {
        messages.append(Array(text.utf8))
    }
}
let totalBytes = messages.reduce(0) { $0 + $1.count }
var load = [Double](repeating: 0, count: 3)
getloadavg(&load, 3)
print(
    "messages \(messages.count), \(totalBytes) bytes, load average \(String(format: "%.1f", load[0])); counting available: \(adtk_malloc_counting_available())"
)

// `--profile`: only the parse loop, many rounds, for a sampling profiler.
if CommandLine.arguments.contains("--profile") {
    var parser = MarkdownParser(
        limits: CommandLine.arguments.contains("--plain") ? MarkdownLimits(maxLeafBytes: 1) : .default)
    for _ in 0 ..< 80 {
        for message in messages {
            parser.reset()
            parser.append(message)
            parser.finish()
        }
    }
    exit(0)
}

// `--phases`: where the time goes: the block phase alone (leaf blocks kept as text), and both, on one reused parser each.
if CommandLine.arguments.contains("--phases") {
    for (name, limits) in [
        ("blocks only (leaves are plain text)", MarkdownLimits(maxLeafBytes: 1)),
        ("blocks and inlines", MarkdownLimits.default)
    ] {
        var parser = MarkdownParser(limits: limits)
        var rounds: [Double] = []
        for _ in 0 ..< 7 {
            let start = now()
            for message in messages {
                parser.reset()
                parser.append(message)
                parser.finish()
            }
            rounds.append(Double(now() - start) / 1e9)
        }
        rounds.sort()
        print(
            String(
                format: "%-38@ median %.3f s (%.1f MB/s)", name as NSString, rounds[3],
                Double(totalBytes) / 1e6 / rounds[3]))
    }
    exit(0)
}

// 1. Whole messages, five rounds.
var rounds: [Double] = []
var slots = 0
for round in 0 ..< 5 {
    let start = now()
    for message in messages {
        let document = MarkdownParser.parse(message)
        if round == 0 { slots += document.blockSlotCount + document.inlineSlotCount }
    }
    rounds.append(Double(now() - start) / 1e9)
}
rounds.sort()
let megabytes = Double(totalBytes) / 1e6
print(
    String(
        format: "parse:      median %.3f s (%.1f MB/s), p10..p90 %.3f..%.3f s over 5 rounds; %d slots", rounds[2],
        megabytes / rounds[2], rounds[0], rounds[4], slots))

// 1b. The same with one parser used for message after message (what a reader of many answers does).
var reuseRounds: [Double] = []
var reused = MarkdownParser()
for _ in 0 ..< 5 {
    let start = now()
    for message in messages {
        reused.reset()
        reused.append(message)
        reused.finish()
    }
    reuseRounds.append(Double(now() - start) / 1e9)
}
reuseRounds.sort()
print(
    String(
        format: "parse, one parser reused: median %.3f s (%.1f MB/s), p10..p90 %.3f..%.3f s", reuseRounds[2],
        megabytes / reuseRounds[2], reuseRounds[0], reuseRounds[4]))

// 2. One message at a time: latency, and allocations.
var perMessage: [Double] = []
for message in messages {
    let start = now()
    _ = MarkdownParser.parse(message)
    perMessage.append(Double(now() - start))
}
perMessage.sort()
print(
    String(
        format: "per message: p50 %.1f us  p95 %.1f us  p99 %.1f us  max %.1f us", percentile(perMessage, 0.5) / 1e3,
        percentile(perMessage, 0.95) / 1e3, percentile(perMessage, 0.99) / 1e3, perMessage.last! / 1e3))
var allocations: [UInt64] = []
let sample = Array(messages.prefix(2000))
for message in sample {
    adtk_malloc_count_begin()
    _ = MarkdownParser.parse(message)
    allocations.append(adtk_malloc_count_end())
}
var reusedAllocations: [UInt64] = []
for message in sample {
    reused.reset()
    adtk_malloc_count_begin()
    reused.append(message)
    reused.finish()
    reusedAllocations.append(adtk_malloc_count_end())
}
let sortedReused = reusedAllocations.sorted()
let sorted = allocations.sorted()
let sampleKB = Double(sample.reduce(0) { $0 + $1.count }) / 1024
print(
    "allocations per message, one parser reused (first 2000): p50 \(sortedReused[sortedReused.count / 2]) p95 \(sortedReused[Int(Double(sortedReused.count) * 0.95)]) max \(sortedReused.last!); \(String(format: "%.1f", Double(reusedAllocations.reduce(0, +)) / sampleKB)) per KB"
)
print(
    "allocations per message (first 2000): p50 \(sorted[sorted.count / 2]) p95 \(sorted[Int(Double(sorted.count) * 0.95)]) max \(sorted.last!); \(String(format: "%.1f", Double(allocations.reduce(0, +)) / sampleKB)) per KB"
)

// 3. A 100 KB answer streamed in 40-byte deltas, a snapshot after each (what a screen asks for).
var answer: [UInt8] = []
for message in messages where message.count > 400 && message.contains(0x0A) {
    answer += message + [0x0A, 0x0A]
    if answer.count >= 100_000 { break }
}
func stream(_ name: String, _ bytes: [UInt8], delta: Int = 40) {
    var deltas: [Double] = []
    var parser = MarkdownParser()
    var offset = 0
    let begin = now()
    while offset < bytes.count {
        let end = min(bytes.count, offset + delta)
        let start = now()
        parser.append(Array(bytes[offset ..< end]))
        let document = parser.snapshot()
        deltas.append(Double(now() - start))
        _ = document.blockSlotCount
        offset = end
    }
    let total = Double(now() - begin) / 1e9
    deltas.sort()
    // Allocations per delta, counted on a second pass so the timing above is not disturbed by the counting hook.
    var counts: [UInt64] = []
    var counted = MarkdownParser()
    var at = 0
    while at < bytes.count {
        let to = min(bytes.count, at + delta)
        let piece = Array(bytes[at ..< to])
        adtk_malloc_count_begin()
        counted.append(piece)
        _ = counted.snapshot()
        counts.append(adtk_malloc_count_end())
        at = to
    }
    counts.sort()
    print(
        "  allocations per delta: p50 \(counts[counts.count / 2]) p95 \(counts[Int(Double(counts.count) * 0.95)]) max \(counts.last!)"
    )
    print(
        String(
            format:
                "stream %-22@ %d bytes, %d deltas, append and snapshot each: total %.3f s; per delta p50 %.1f us  p95 %.1f us  p99 %.1f us  max %.1f us",
            name as NSString, bytes.count, deltas.count, total, percentile(deltas, 0.5) / 1e3,
            percentile(deltas, 0.95) / 1e3, percentile(deltas, 0.99) / 1e3, deltas.last! / 1e3))
}
stream("real answers", answer)
// The worst shapes for a parser that redoes the open block: one paragraph that never ends, and one code block that never closes.
let words = Array(
    "The quick brown fox jumps over the lazy dog, with `code`, **bold**, *emphasis* and a [link](https://example.com/path) in it. "
        .utf8)
var paragraph: [UInt8] = []
while paragraph.count < 100_000 { paragraph += words }
stream("one 100 KB paragraph", paragraph)
var code = Array("```swift\n".utf8)
while code.count < 100_000 {
    code += Array("let value = compute(items.map { $0.size }.reduce(0, +)) // a line of code\n".utf8)
}
stream("one 100 KB code block", code)
