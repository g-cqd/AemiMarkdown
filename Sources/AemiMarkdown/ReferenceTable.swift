/// The link reference definitions of a document: `[label]: destination "title"`, found by their normalized label.
struct ReferenceTable: Sendable {
    struct Reference: Sendable {
        var destination: Range<Int>
        var title: Range<Int>?
    }

    private var entries: [[UInt8]: Reference] = [:]
    private var footnotes: Set<[UInt8]> = []

    var isEmpty: Bool { entries.isEmpty && footnotes.isEmpty }

    /// Whether any link reference definition has been recorded.
    var hasDefinitions: Bool { !entries.isEmpty }

    /// How many definitions, footnotes included, were offered to the table since it was last emptied, whether they were kept or not: an edit that
    /// parsed some may have changed what every link in the document means.
    private(set) var insertAttempts = 0

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        footnotes.removeAll(keepingCapacity: true)
        insertAttempts = 0
    }

    /// Records a definition. The first definition of a label wins. The key is one allocation.
    mutating func insert(label: some Collection<UInt8>, _ reference: Reference) {
        insertAttempts += 1
        var key: [UInt8] = []
        Self.normalize(label, into: &key)
        if !key.isEmpty, entries[key] == nil { entries[key] = reference }
    }

    /// Records that a footnote has this label (the first one is the one that counts).
    mutating func insertFootnote(label: some Collection<UInt8>) {
        insertAttempts += 1
        var key: [UInt8] = []
        Self.normalize(label, into: &key)
        if !key.isEmpty { footnotes.insert(key) }
    }

    /// Moves the destination and title of every definition that lies at or after `offset` by `distance` bytes: the source changed before them.
    /// - Returns: whether there was one.
    @discardableResult
    mutating func shiftOffsets(from offset: Int, by distance: Int) -> Bool {
        var moved = false
        for index in entries.values.indices where entries.values[index].destination.lowerBound >= offset {
            moved = true
            guard distance != 0 else { continue }
            let destination = entries.values[index].destination
            entries.values[index].destination =
                (destination.lowerBound + distance) ..< (destination.upperBound + distance)
            if let title = entries.values[index].title {
                entries.values[index].title = (title.lowerBound + distance) ..< (title.upperBound + distance)
            }
        }
        return moved
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
        guard !ascii, Self.changesWithCase(out) else { return }
        // Case folding is not lowercasing (`ẞ` and `ß` both fold to `ss`); lower, upper, lower gets the full folds the spec's examples need.
        out = Array(String(decoding: out, as: UTF8.self).lowercased().uppercased().lowercased().utf8)
    }

    /// Whether any character of the UTF-8 text `bytes` has a case mapping (or the text is not valid UTF-8, which the folding below replaces). A label in a script
    /// without case (Chinese, Japanese, Arabic, emoji) is its own folded form, and does not need the three passes over a `String`.
    private static func changesWithCase(_ bytes: [UInt8]) -> Bool {
        var parser = Unicode.UTF8.ForwardParser()
        var iterator = bytes.makeIterator()
        while true {
            switch parser.parseScalar(from: &iterator) {
                case .valid(let encoded):
                    if Unicode.UTF8.decode(encoded).properties.changesWhenCaseMapped { return true }
                case .emptyInput: return false
                case .error: return true
            }
        }
    }
}
