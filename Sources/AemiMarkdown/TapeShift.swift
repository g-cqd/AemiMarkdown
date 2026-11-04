/// What to add to the `low` field of each kind of slot when the bytes or the slots before it have moved (ADR-0003, phase B).
///
/// A container's `low` is a tape index, a leaf block's is an index on the inline tape, a range's is a byte offset, and a marker's is a value that does not
/// name a place. So the shift is a table of sixteen words, one for each tag, and a slot moves by the word its tag names: no `switch` per slot.
/// The value is four words; the table is made on the stack when a tape is shifted.
struct TapeShift: Sendable {
    let container: UInt64
    let leaf: UInt64
    let range: UInt64
    let isZero: Bool
    /// A range slot whose offset is below this did not move: a link names a definition, and a definition may stand before the edit.
    let rangeThreshold: Int

    init(container: Int = 0, leaf: Int = 0, range: Int = 0, rangesFrom threshold: Int = 0) {
        self.container = UInt64(bitPattern: Int64(container))
        self.leaf = UInt64(bitPattern: Int64(leaf))
        self.range = UInt64(bitPattern: Int64(range))
        isZero = container == 0 && leaf == 0 && range == 0
        rangeThreshold = threshold
    }
}
