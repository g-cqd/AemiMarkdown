@available(macOS 26.0, *)
extension NativeMarker {
    /// What checking a task off or on writes: its `[ ]` becomes `[x]`, and `[x]` or `[X]` becomes `[ ]`.
    /// - Parameters:
    ///   - source: The document's bytes.
    ///   - offset: Where the task's `[` is, as its marker says.
    /// - Returns: The bytes to replace and what replaces them, or nil when no box is there (the document changed under it).
    public static func toggle(in source: some RandomAccessCollection<UInt8>, at offset: Int) -> (Range<Int>, String)? {
        guard offset >= 0, offset + 3 <= source.count else { return nil }
        let start = source.index(source.startIndex, offsetBy: offset)
        let bytes = Array(source[start ..< source.index(start, offsetBy: 3)])
        guard bytes[0] == UInt8(ascii: "["), bytes[2] == UInt8(ascii: "]") else { return nil }
        switch bytes[1] {
            case UInt8(ascii: " "): return (offset ..< offset + 3, "[x]")
            case UInt8(ascii: "x"), UInt8(ascii: "X"): return (offset ..< offset + 3, "[ ]")
            default: return nil
        }
    }
}
