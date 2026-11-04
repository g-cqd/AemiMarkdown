internal import AemiKernel

extension InlineParser {
    /// Folds the result of a reference lookup into the leaf block's stamp: what the label (as the block wrote it, in `text[label]`) names, or that it names
    /// nothing. The label is hashed as written, not normalized: the stamp has to change when the meaning does, and it is the same block's bytes either way.
    mutating func stampResolution(label: Range<Int>, _ found: ReferenceTable.Reference?) {
        var value = text.withUnsafeBytes { raw in
            // SAFETY: `label` lies inside `text`, which the caller took it from.
            unsafe WyHash.hash(
                UnsafeRawBufferPointer(rebasing: raw[label]),
                seed: found == nil ? 0x4E4F_4E45 : 0x5245_4631
            )
        }
        if let found {
            value ^= hash(source, found.destination).rotatedLeft(17)
            if let title = found.title { value ^= hash(source, title).rotatedLeft(41) }
        }
        fold(value)
    }

    /// Folds in that a footnote with the label in `referenceKey` exists.
    mutating func stampFootnote() { fold(Self.hash(referenceKey, seed: 0x464E_4F54)) }

    private mutating func fold(_ value: UInt64) {
        resolutionStamp = (resolutionStamp.rotatedLeft(23) ^ value) &* 0x9E37_79B9_7F4A_7C15
        if resolutionStamp == 0 { resolutionStamp = 1 }
    }

    private static func hash(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        bytes.withUnsafeBytes { unsafe WyHash.hash($0, seed: seed) }
    }

    private func hash(_ source: ContiguousArray<UInt8>, _ range: Range<Int>) -> UInt64 {
        let range = range.clamped(to: 0 ..< source.count)
        return source.withUnsafeBytes { raw in
            // SAFETY: `range` is clamped to the source, so it names bytes inside the buffer the closure is lent.
            unsafe WyHash.hash(UnsafeRawBufferPointer(rebasing: raw[range]), seed: 0x4445_5354)
        }
    }
}

extension UInt64 {
    @inline(__always)
    func rotatedLeft(_ count: UInt64) -> UInt64 { self << count | self >> (64 - count) }
}
