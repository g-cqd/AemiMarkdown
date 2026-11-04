import Foundation

/// The public documents that `Benchmarks/Corpus/fetch.py setup` downloads into a cache outside the repository (`AEMI_MARKDOWN_CORPUS` says where else).
/// Tests that need them are disabled, with the reason, when the cache is empty: a suite that ran on nothing would look like a pass.
enum PublicCorpus {
    static let directory: String = {
        let base =
            ProcessInfo.processInfo.environment["AEMI_MARKDOWN_CORPUS"]
            ?? NSString(string: "~/Library/Caches/AemiMarkdownCorpus").expandingTildeInPath
        return base + "/files"
    }()

    static var isAvailable: Bool { !((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).isEmpty }

    /// The documents no larger than `limit` bytes, in a fixed order.
    static func documents(upTo limit: Int) -> [[UInt8]] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
        return names.compactMap { FileManager.default.contents(atPath: directory + "/" + $0) }
            .filter { $0.count <= limit }.map { Array($0) }
    }
}
