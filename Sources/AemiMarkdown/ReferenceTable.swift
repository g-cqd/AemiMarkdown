/// The link reference definitions of a document: `[label]: destination "title"`, found by their normalized label.
struct ReferenceTable: Sendable {
    struct Reference: Sendable {
        var destination: Range<Int>
        var title: Range<Int>?
    }

    private var entries: [[UInt8]: Reference] = [:]
    private var footnotes: Set<[UInt8]> = []

    var isEmpty: Bool { entries.isEmpty && footnotes.isEmpty }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        footnotes.removeAll(keepingCapacity: true)
    }

    /// Records a definition. The first definition of a label wins. The key is one allocation.
    mutating func insert(label: some Collection<UInt8>, _ reference: Reference) {
        var key: [UInt8] = []
        Self.normalize(label, into: &key)
        if !key.isEmpty, entries[key] == nil { entries[key] = reference }
    }

    /// Records that a footnote has this label (the first one is the one that counts).
    mutating func insertFootnote(label: some Collection<UInt8>) {
        var key: [UInt8] = []
        Self.normalize(label, into: &key)
        if !key.isEmpty { footnotes.insert(key) }
    }

    /// Whether a footnote has this label, using `key` as scratch.
    func hasFootnote(label: some Collection<UInt8>, scratch key: inout [UInt8]) -> Bool {
        guard !footnotes.isEmpty else { return false }
        Self.normalize(label, into: &key)
        return footnotes.contains(key)
    }

    /// The definition of the label, using `key` as scratch for its normalized form, so a lookup allocates nothing for an ASCII label.
    func find(label: some Collection<UInt8>, scratch key: inout [UInt8]) -> Reference? {
        Self.normalize(label, into: &key)
        return entries[key]
    }

    /// Writes the matching form of a label into `out`: no leading or trailing whitespace, runs of whitespace as one space, and Unicode case folded.
    /// - Complexity: O(label length); a label with non-ASCII bytes allocates.
    static func normalize(_ label: some Collection<UInt8>, into out: inout [UInt8]) {
        out.removeAll(keepingCapacity: true)
        var pendingSpace = false
        var ascii = true
        for byte in label {
            if ASCIIClass.isWhitespace(byte) {
                pendingSpace = !out.isEmpty
            } else {
                if pendingSpace {
                    out.append(0x20)
                    pendingSpace = false
                }
                if byte >= 0x80 {
                    ascii = false
                    out.append(byte)
                } else {
                    out.append(byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte)
                }
            }
        }
        guard !ascii else { return }
        // Case folding is not lowercasing (`ẞ` and `ß` both fold to `ss`); lower, upper, lower gets the full folds the spec's examples need.
        out = Array(String(decoding: out, as: UTF8.self).lowercased().uppercased().lowercased().utf8)
    }
}
