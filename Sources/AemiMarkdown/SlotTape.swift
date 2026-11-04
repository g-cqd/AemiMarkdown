internal import AemiKernel

/// A tape of slots in two parts: a committed prefix that is final and shared, and a small tail that is still changing (ADR-0001).
///
/// Indices are global: a slot's index does not change when the tail is committed. Appends go to the tail; reads and writes find the part an index is in.
/// A snapshot of an open document is the committed part, shared, and a copy of the tail, so it costs what the open top-level block costs and not what the
/// document costs.
struct SlotTape: Sendable {
    private(set) var committed: ContiguousArray<UInt64> = []
    private(set) var tail: ContiguousArray<UInt64> = []

    var count: Int { committed.count + tail.count }
    /// How many slots are not yet committed.
    var tailCount: Int { tail.count }
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
        if !committed.isEmpty { committed.removeAll(keepingCapacity: true) }
        if !tail.isEmpty { tail.removeAll(keepingCapacity: true) }
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

extension SlotTape {
    /// Every slot, in order. The tape must have nothing in its tail.
    var committedSlots: ContiguousArray<UInt64> { committed }

    /// Moves each slot from `start` on by its kind's distance. The tail is committed first.
    /// - Complexity: O(count - start), one table lookup and one addition per slot.
    mutating func shift(from start: Int, to stop: Int? = nil, _ shift: TapeShift) {
        commit()
        let stop = Swift.min(stop ?? committed.count, committed.count)
        guard !shift.isZero, start < stop else { return }
        let threshold = shift.rangeThreshold
        withUnsafeTemporaryAllocation(of: UInt64.self, capacity: 16) { table in
            for tag in 0 ..< 16 { unsafe table[tag] = 0 }
            unsafe table[Int(SlotShape.container.rawValue)] = shift.container
            unsafe table[Int(SlotShape.leafBlock.rawValue)] = shift.leaf
            unsafe table[Int(SlotShape.range.rawValue)] = shift.range
            committed.withUnsafeMutableBufferPointer { buffer in
                var index = start
                while index < stop {
                    // SAFETY: `index < stop <= buffer.count`, and a tag is four bits, so it is below the table's sixteen words.
                    let slot = unsafe buffer[index]
                    var distance = unsafe table[Int(slot >> 60)]
                    if slot >> 60 == UInt64(SlotShape.range.rawValue), Int(slot & TapeSlot.lowMask) < threshold {
                        distance = 0
                    }
                    unsafe buffer[index] = slot &+ distance
                    index += 1
                }
            }
        }
    }

    /// Replaces the slots in `range` with `slots` and moves each slot after them by its kind's distance in `tailShift`.
    /// - Complexity: O(count - range.lowerBound): the tail moves once and is shifted once.
    mutating func replace(_ range: Range<Int>, with slots: ContiguousArray<UInt64>, tailShift: TapeShift) {
        commit()
        committed.replaceSubrange(range, with: slots)
        shift(from: range.lowerBound + slots.count, tailShift)
    }
}

extension SlotTape {
    /// Moves what the entries of `stride` slots hold, from the entry at `start` on: the slot at `packedAt`, if there is one, holds two offsets (a
    /// range: low and high halves) that move by `packedDelta`, and the slot at `slotAt` holds a tape index that moves by `slotDelta`.
    mutating func shiftEntries(
        from start: Int,
        stride: Int,
        packedAt: Int?,
        packedDelta: Int,
        slotAt: Int,
        slotDelta: Int
    ) {
        commit()
        guard start < committed.count, packedDelta != 0 || slotDelta != 0 else { return }
        let packed = UInt64(bitPattern: Int64(packedDelta)) &+ UInt64(bitPattern: Int64(packedDelta) << 32)
        let slotMove = UInt64(bitPattern: Int64(slotDelta))
        var index = start
        while index + stride <= committed.count {
            if let packedAt { committed[index + packedAt] = committed[index + packedAt] &+ packed }
            committed[index + slotAt] = committed[index + slotAt] &+ slotMove
            index += stride
        }
    }
}
