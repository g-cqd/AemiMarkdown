internal import AemiKernels

/// Safe entry points to Aemi's SIMD byte scans, over the arrays the parser keeps.
enum ByteScan {
    /// The index in `bytes`, at or after `start`, of the first byte in `set`, or `bytes.count`.
    static func firstIndex(inSet set: AemiKernels.ByteSet, in bytes: ContiguousArray<UInt8>, from start: Int) -> Int {
        guard start < bytes.count else { return bytes.count }
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return bytes.count }
            // SAFETY: as above.
            let found = unsafe AemiKernels.firstIndex(inSet: set, base: base + start, count: bytes.count - start)
            return start + found
        }
    }

    /// As ``firstIndex(inSet:in:from:)``, looking only before `limit`: `limit` if none is there.
    static func firstIndex(
        inSet set: AemiKernels.ByteSet,
        in bytes: ContiguousArray<UInt8>,
        from start: Int,
        before limit: Int
    ) -> Int {
        let limit = Swift.min(limit, bytes.count)
        guard start < limit else { return limit }
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return limit }
            // SAFETY: `start < limit <= bytes.count`, so `base + start` is valid for `limit - start` bytes, the count the kernel is given.
            let found = unsafe AemiKernels.firstIndex(inSet: set, base: base + start, count: limit - start)
            return start + found
        }
    }

    /// The set of `bytes`: a set the nibble tables cannot hold is a mistake in this file, found by the first test that runs.
    private static func nibbleSet(_ bytes: [UInt8], _ name: String) -> AemiKernels.ByteSet {
        guard let set = AemiKernels.ByteSet(bytes) else { preconditionFailure("\(name) do not fit in nibble tables") }
        return set
    }

    /// A pipe and a backslash: what ends a table cell, or hides the pipe that would.
    static let cellStops: AemiKernels.ByteSet = nibbleSet(Array("|\\".utf8), "cell stops")

    /// The bytes that start something in a leaf block: a line ending, a backslash, a backtick, `*`, `_`, `~`, `[`, `]`, `!`, `<` and `&`. Six rows of nibbles, so the tables hold it exactly.
    static let inlineSpecials: AemiKernels.ByteSet = nibbleSet(Array("\n\\`*_~[]!<&$".utf8), "inline specials")

    /// The bytes a bare link can start at: the `:` of a scheme, the `@` of an address, and the `w` of `www.`.
    static let autolinkStarts: AemiKernels.ByteSet = nibbleSet(Array(":@w".utf8), "link starts")

    /// Line feed and carriage return.
    static let lineEndings: AemiKernels.ByteSet = nibbleSet([0x0A, 0x0D], "line endings")

    /// The C0 controls other than tab, line feed and carriage return, and DEL: what a renderer must neutralise.
    static let unsafeControls: AemiKernels.ByteSet = nibbleSet(
        (0 ..< 0x20).filter { $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }.map { UInt8($0) } + [0x7F],
        "the controls"
    )
}
