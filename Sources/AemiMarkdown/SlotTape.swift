/// A tape of slots in two parts: a committed prefix that is final and shared, and a small tail that is still changing (ADR-0001).
///
/// Indices are global: a slot's index does not change when the tail is committed. Appends go to the tail; reads and writes find the part an index is in.
/// A snapshot of an open document is the committed part, shared, and a copy of the tail, so it costs what the open top-level block costs and not what the
/// document costs.
struct SlotTape: Sendable {
    private(set) var committed: ContiguousArray<UInt64> = []
    private(set) var tail: ContiguousArray<UInt64> = []

    var count: Int { committed.count + tail.count }
    var last: UInt64? { tail.last ?? committed.last }

    subscript(index: Int) -> UInt64 {
        get { index < committed.count ? committed[index] : tail[index - committed.count] }
        set {
            if index < committed.count { committed[index] = newValue } else { tail[index - committed.count] = newValue }
        }
    }

    mutating func append(_ slot: UInt64) { tail.append(slot) }

    /// Makes room for `count` more slots in each part, so a document whose size is known grows its tapes once.
    mutating func reserveCapacity(_ count: Int) {
        committed.reserveCapacity(committed.count + count)
        tail.reserveCapacity(count)
    }

    /// Empties the tape and keeps the room it grew. Storage that a snapshot still shares is left to that snapshot and replaced.
    mutating func removeAll() {
        committed.removeAll(keepingCapacity: true)
        tail.removeAll(keepingCapacity: true)
    }

    /// Removes the last slot, which must still be in the tail: a slot is committed only after the block it belongs to has closed.
    mutating func removeLast() {
        precondition(!tail.isEmpty, "the last slot is already committed")
        tail.removeLast()
    }

    /// Makes the tail final.
    mutating func commit() {
        guard !tail.isEmpty else { return }
        committed.append(contentsOf: tail)
        tail.removeAll(keepingCapacity: true)
    }
}
