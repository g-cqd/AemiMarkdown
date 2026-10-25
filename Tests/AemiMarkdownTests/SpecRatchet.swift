import Foundation

/// The examples the parser is known to fail, and why (ADR-0001, decision 6). The list shrinks and never gains an entry: the suite fails
/// for an example that fails and is not listed, and for one that passes and is. `Scripts/update-ratchet.sh` rewrites the file after a fix.
enum SpecRatchet {
    static func knownFailing() throws -> Set<String> {
        guard let url = Bundle.module.url(forResource: "known-failing", withExtension: "txt", subdirectory: "Fixtures")
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return Set(
            text.split(separator: "\n")
                .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { String($0.split(separator: "#", maxSplits: 1)[0]).trimmingCharacters(in: .whitespaces) })
    }
}
