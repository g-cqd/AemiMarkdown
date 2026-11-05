import Testing

@testable import MarkdownLookKit

@Suite("The output buffer")
struct OutputBufferTests {
    @Test func `it holds what was appended, in order, across growth`() {
        var buffer = OutputBuffer(capacity: 64)
        var expected: [UInt8] = []
        for round in 0 ..< 5_000 {
            switch round % 5 {
                case 0:
                    buffer.append(UInt8(round & 0x7F))
                    expected.append(UInt8(round & 0x7F))
                case 1:
                    buffer += "<p>"
                    expected += Array("<p>".utf8)
                case 2:
                    let piece = Array(repeating: UInt8(round & 0x7F), count: round % 97)
                    buffer.append(contentsOf: piece)
                    expected += piece
                case 3:
                    let text = String(repeating: "é", count: round % 13)
                    buffer += text
                    expected += Array(text.utf8)
                default:
                    let piece = Array(repeating: UInt8(round & 0x7F), count: round % 31)
                    buffer.append(contentsOf: piece[...])
                    expected += piece
            }
        }
        #expect(buffer.count == expected.count)
        #expect(buffer.array == expected)
        #expect(buffer.bytes(from: 1_000) == Array(expected[1_000...]))
    }

    @Test func `a copy keeps what it had when the original grows`() {
        var original = OutputBuffer(capacity: 64)
        original.append(contentsOf: Array("hello".utf8))
        let copy = original
        original.append(contentsOf: Array(repeating: 0x41, count: 10_000))
        #expect(copy.array == Array("hello".utf8))
        #expect(original.count == 10_005)
    }

    @Test func `truncating cuts back, and appending goes on from there`() {
        var buffer = OutputBuffer()
        buffer.append(contentsOf: Array("abcdef".utf8))
        buffer.truncate(to: 3)
        buffer.append(contentsOf: Array("XY".utf8))
        #expect(buffer.array == Array("abcXY".utf8))
        buffer.truncate(to: 0)
        #expect(buffer.array.isEmpty)
    }

    @Test func `an empty append changes nothing`() {
        var buffer = OutputBuffer()
        buffer.append(contentsOf: [])
        buffer.append(contentsOf: [UInt8]()[...])
        buffer += ""
        #expect(buffer.count == 0)
    }
}
