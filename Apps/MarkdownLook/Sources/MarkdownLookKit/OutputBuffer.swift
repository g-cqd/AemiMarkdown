/// The page the writer is making, as UTF-8, in storage it grows itself.
///
/// An `Array` checks at every append that it is the only owner of its storage and that there is room, and a writer that appends a few bytes at a time (a tag, a run of text, another tag) pays for both millions of times. The buffer keeps its pointer, count and capacity
/// inline, so an append is one comparison and a copy; growth doubles, as an array's does. A copy of the value shares the block, so the owner of one writer must not append to two copies (nothing does: the writer owns its buffer and hands out `array` at the end).
///
/// Every index is checked, and appends only write inside the block the buffer allocated, so the unsafe part is the pointer arithmetic after the check.
@safe
struct OutputBuffer {
    /// Owns the block and frees it.
    @safe private final class Block {
        let pointer: UnsafeMutablePointer<UInt8>
        init(capacity: Int) { unsafe pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity) }
        deinit { unsafe pointer.deallocate() }
    }

    private var block: Block
    // SAFETY: `block.pointer`, valid for `capacity` bytes while `block` lives.
    private var base: UnsafeMutablePointer<UInt8>
    private(set) var count = 0
    private var capacity: Int

    init(capacity: Int = 256) {
        self.capacity = Swift.max(capacity, 64)
        block = Block(capacity: self.capacity)
        unsafe base = block.pointer
    }

    subscript(index: Int) -> UInt8 {
        precondition(index >= 0 && index < count, "output index out of range")
        return unsafe base[index]
    }

    mutating func reserveCapacity(_ minimum: Int) {
        if minimum > capacity { grow(to: minimum) }
    }

    @inline(__always)
    mutating func append(_ byte: UInt8) {
        if count == capacity { grow(to: capacity * 2) }
        unsafe base[count] = byte
        count += 1
    }

    /// Appends the `length` bytes at `source`, which must not overlap the buffer.
    @inline(__always)
    mutating func append(contentsOf source: UnsafeBufferPointer<UInt8>) {
        let length = source.count
        guard length > 0, let from = source.baseAddress else { return }
        if count + length > capacity { grow(to: Swift.max(capacity * 2, count + length)) }
        unsafe (base + count).update(from: from, count: length)
        count += length
    }

    mutating func append(contentsOf bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { unsafe append(contentsOf: $0) }
    }

    mutating func append(contentsOf bytes: ArraySlice<UInt8>) {
        bytes.withUnsafeBufferPointer { unsafe append(contentsOf: $0) }
    }

    /// Appends a literal: its bytes are in the binary.
    mutating func append(_ literal: StaticString) {
        unsafe append(contentsOf: UnsafeBufferPointer(start: literal.utf8Start, count: literal.utf8CodeUnitCount))
    }

    mutating func append(_ string: String) {
        var string = string
        string.withUTF8 { unsafe append(contentsOf: $0) }
    }

    /// Cuts the buffer back to its first `length` bytes.
    mutating func truncate(to length: Int) {
        precondition(length >= 0 && length <= count, "truncate beyond the end")
        count = length
    }

    /// A copy of the bytes from `start` on.
    func bytes(from start: Int) -> [UInt8] {
        precondition(start >= 0 && start <= count, "output index out of range")
        return unsafe Array(UnsafeBufferPointer(start: base + start, count: count - start))
    }

    /// The page as an array (one copy).
    var array: [UInt8] { bytes(from: 0) }

    static func += (lhs: inout OutputBuffer, rhs: StaticString) { lhs.append(rhs) }

    @_disfavoredOverload
    static func += (lhs: inout OutputBuffer, rhs: String) { lhs.append(rhs) }

    private mutating func grow(to newCapacity: Int) {
        let fresh = Block(capacity: newCapacity)
        unsafe fresh.pointer.update(from: base, count: count)
        block = fresh
        unsafe base = fresh.pointer
        capacity = newCapacity
    }
}
