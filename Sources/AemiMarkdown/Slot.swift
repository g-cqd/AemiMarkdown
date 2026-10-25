internal import AemiKernel

/// How a node sits on a tape, in the tag of its slot (`TapeSlot`: tag 4 bits, aux 28 bits, low 32 bits).
///
/// | shape | `low` | aux |
/// |---|---|---|
/// | ``container`` | index after the subtree | kind (6 bits), payload (22 bits) |
/// | ``leafBlock`` | index of the first slot of its inline run | kind, payload |
/// | ``range`` | offset of the first source byte | kind, length (22 bits) |
/// | ``marker`` | offset of the source byte it stands at, or its value | kind, payload |
enum SlotShape: UInt8 {
    case container = 0
    case leafBlock
    case range
    case marker
}

/// Packing and unpacking of one slot. Every `make` clamps nothing: a caller checks `MarkdownLimits` first, and the debug
/// preconditions say which limit would have been broken.
enum Slot {
    static let payloadBits: UInt64 = 22
    static let payloadMask: UInt64 = (1 << payloadBits) - 1
    /// The longest source range one slot can name; a longer one is split across slots.
    static let maxRange = Int(payloadMask)

    @inline(__always)
    static func make(_ shape: SlotShape, _ kind: NodeKind, payload: Int, low: Int) -> UInt64 {
        precondition(payload >= 0 && UInt64(payload) <= payloadMask, "slot payload out of range")
        precondition(low >= 0 && low <= TapeSlot.maxLow, "slot offset out of range")
        let aux = UInt64(kind.rawValue) << payloadBits | UInt64(payload)
        return TapeSlot.make(tag: shape.rawValue, aux: aux, low: low)
    }

    @inline(__always)
    static func shape(_ slot: UInt64) -> SlotShape { SlotShape(rawValue: TapeSlot.tag(slot)) ?? .marker }

    @inline(__always)
    static func kind(_ slot: UInt64) -> NodeKind {
        NodeKind(rawValue: UInt8(truncatingIfNeeded: TapeSlot.aux(slot) >> payloadBits)) ?? .text
    }

    @inline(__always)
    static func payload(_ slot: UInt64) -> Int { Int(TapeSlot.aux(slot) & payloadMask) }

    @inline(__always)
    static func low(_ slot: UInt64) -> Int { TapeSlot.low(slot) }

    /// `slot` with a new `low`: how a container learns where its subtree ends.
    @inline(__always)
    static func withLow(_ slot: UInt64, _ low: Int) -> UInt64 {
        (slot & ~TapeSlot.lowMask) | (UInt64(truncatingIfNeeded: low) & TapeSlot.lowMask)
    }

    /// `slot` with a new payload: how a list learns that it is tight.
    @inline(__always)
    static func withPayload(_ slot: UInt64, _ payload: Int) -> UInt64 {
        let aux = (TapeSlot.aux(slot) & ~payloadMask) | UInt64(payload)
        return TapeSlot.make(tag: TapeSlot.tag(slot), aux: aux, low: TapeSlot.low(slot))
    }
}
