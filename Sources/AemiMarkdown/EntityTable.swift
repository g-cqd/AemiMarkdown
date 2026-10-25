/// The HTML5 named character references (2,125 with a semicolon), looked up by name.
///
/// The data is generated (`EntityTable+Data.swift`). It is read once into a byte array and an array of line starts, and a lookup is a binary search over them.
enum EntityTable {
    /// The longest name in the table, `CounterClockwiseContourIntegral`.
    static let maxNameLength = 31

    private static let bytes: [UInt8] = data.withUTF8Buffer { buffer in
        // SAFETY: the buffer is the static string's own bytes, valid for the whole run of the program, and read here only to copy.
        unsafe Array(buffer)
    }

    /// Where each line starts in `bytes`.
    private static let lineStarts: [Int] = {
        var starts: [Int] = []
        var start = 0
        for (index, byte) in bytes.enumerated() where byte == 0x0A {
            if index > start { starts.append(start) }
            start = index + 1
        }
        return starts
    }()

    /// The code points of an entity: one, or two for a few.
    struct Entity {
        var first: Unicode.Scalar
        var second: Unicode.Scalar?
    }

    /// The code points of the entity `name` (without `&` and `;`), or nil. Allocates nothing.
    /// - Complexity: O(log n) names, each compared in O(name length).
    static func lookup(_ name: some RandomAccessCollection<UInt8>) -> Entity? {
        guard name.count <= maxNameLength, !name.isEmpty else { return nil }
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let start = lineStarts[middle]
            switch compare(name, at: start) {
                case 0: return entity(at: start + name.count + 1)
                case let order where order < 0: high = middle - 1
                default: low = middle + 1
            }
        }
        return nil
    }

    /// Negative if `name` sorts before the entry at `start`, positive if after, and 0 if they are the same name.
    private static func compare(_ name: some RandomAccessCollection<UInt8>, at start: Int) -> Int {
        var index = 0
        for byte in name {
            let entry = bytes[start + index]
            if entry == 0x20 { return 1 }  // the entry's name is shorter, so it sorts first
            if byte != entry { return byte < entry ? -1 : 1 }
            index += 1
        }
        return bytes[start + index] == 0x20 ? 0 : -1
    }

    private static func entity(at start: Int) -> Entity {
        var first: Unicode.Scalar?
        var value: UInt32 = 0
        var index = start
        while index < bytes.count, bytes[index] != 0x0A {
            let byte = bytes[index]
            if byte == 0x20 {
                first = Unicode.Scalar(value) ?? "\u{FFFD}"
                value = 0
            } else {
                value = value * 16 + UInt32(byte <= 0x39 ? byte - 0x30 : byte - 0x61 + 10)
            }
            index += 1
        }
        let last = Unicode.Scalar(value) ?? "\u{FFFD}"
        if let first { return Entity(first: first, second: last) }
        return Entity(first: last, second: nil)
    }
}
