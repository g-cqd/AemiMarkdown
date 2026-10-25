/// The link reference definitions of a document: `[label]: destination "title"`, found by their normalized label.
struct ReferenceTable: Sendable {
    struct Reference: Sendable {
        var destination: Range<Int>
        var title: Range<Int>?
    }

    private var entries: [[UInt8]: Reference] = [:]

    var isEmpty: Bool { entries.isEmpty }

    /// Records a definition. The first definition of a label wins.
    mutating func insert(label: some Collection<UInt8>, _ reference: Reference) {
        let key = Self.normalize(label)
        if !key.isEmpty, entries[key] == nil { entries[key] = reference }
    }

    func find(label: some Collection<UInt8>) -> Reference? {
        entries[Self.normalize(label)]
    }

    /// The matching form of a label: no leading or trailing whitespace, runs of whitespace as one space, and Unicode case folded.
    /// - Complexity: O(label length); non-ASCII labels allocate.
    static func normalize(_ label: some Collection<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(label.count)
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
        guard !ascii else { return out }
        // Case folding is not lowercasing (`ẞ` and `ß` both fold to `ss`); lower, upper, lower gets the full folds the spec's examples need.
        return Array(String(decoding: out, as: UTF8.self).lowercased().uppercased().lowercased().utf8)
    }
}
