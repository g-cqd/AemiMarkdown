internal import AppKit
internal import Foundation
internal import Observation
internal import SwiftUI

/// A place in the document: a row, and in a text row the UTF-16 offset in the text as written; in any other row 0 (before it) or 1 (after it).
@available(macOS 26.0, *)
struct SelectionPoint: Comparable, Equatable {
    var row: Int
    var offset: Int

    static func < (a: Self, b: Self) -> Bool { (a.row, a.offset) < (b.row, b.offset) }
}

/// Where a text row's glyphs are, in the text's own coordinates, as its last drawing laid them out: for each slice of the layout its place in the text as written and its box.
@available(macOS 26.0, *)
struct TextGeometry: Sendable {
    struct Slice: Sendable {
        var start: Int
        var end: Int
        var rect: CGRect
        var line: Int
    }

    var slices: [Slice] = []
    var lines: [CGRect] = []

    /// The offset in the text as written that a point is at: the line it is on (the nearest), then the edge of the glyph it is nearer.
    func offset(at point: CGPoint) -> Int? {
        guard !lines.isEmpty else { return nil }
        var line = 0
        var best = CGFloat.greatestFiniteMagnitude
        for (index, rect) in lines.enumerated() {
            let distance = point.y < rect.minY ? rect.minY - point.y : (point.y > rect.maxY ? point.y - rect.maxY : 0)
            if distance < best {
                best = distance
                line = index
            }
        }
        let here = slices.filter { $0.line == line }
        guard let first = here.first, let last = here.last else { return nil }
        if point.x <= first.rect.minX { return first.start }
        if point.x >= last.rect.maxX { return last.end }
        for slice in here where point.x < slice.rect.maxX {
            return point.x < slice.rect.midX ? slice.start : slice.end
        }
        return last.end
    }

    /// The boxes, one to a line, of the text from `start` to `end`.
    func boxes(from start: Int, to end: Int) -> [CGRect] {
        var boxes: [Int: CGRect] = [:]
        for slice in slices where slice.end > start && slice.start < end {
            boxes[slice.line] = boxes[slice.line].map { $0.union(slice.rect) } ?? slice.rect
        }
        return boxes.sorted { $0.key < $1.key }
            .map { box in
                let line = lines[box.key]
                return CGRect(x: box.value.minX, y: line.minY, width: box.value.width, height: line.height)
            }
    }
}

/// What the renderers write and the selection reads: the geometry of each text row. Drawing may happen off the main thread, hence the lock.
@available(macOS 26.0, *)
final class GeometryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [Int: TextGeometry] = [:]

    func set(_ geometry: TextGeometry, row: Int) {
        lock.lock()
        rows[row] = geometry
        lock.unlock()
    }

    func geometry(row: Int) -> TextGeometry? {
        lock.lock()
        defer { lock.unlock() }
        return rows[row]
    }
}

/// How a text row's layout is read into a `TextGeometry`: with the map from the unit of the text as laid out to the text as written (`NativeRichText.text`).
@available(macOS 26.0, *)
struct SelectionRecorder: Sendable {
    let store: GeometryStore
    let row: Int
    let map: [Int]

    /// The UTF-16 offset a character index holds: the type keeps it in a field the module does not export, so it is read by reflection (and a layout whose indices cannot be read is not selectable).
    private static func unit(of index: Text.Layout.CharacterIndex) -> Int? {
        Mirror(reflecting: index).children.first { $0.label == "value" }?.value as? Int
    }

    func capture(_ layout: Text.Layout) {
        var geometry = TextGeometry()
        var starts: [(start: Int, rect: CGRect, line: Int)] = []
        for (number, line) in layout.enumerated() {
            geometry.lines.append(line.typographicBounds.rect)
            for run in line {
                for slice in run {
                    guard let first = slice.characterIndices.first, let index = Self.unit(of: first) else { continue }
                    starts.append(
                        (map[Swift.min(Swift.max(0, index), map.count - 1)], slice.typographicBounds.rect, number)
                    )
                }
            }
        }
        let total = map.last ?? 0
        for (index, item) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].start : total
            geometry.slices.append(
                .init(start: item.start, end: Swift.max(item.start, end), rect: item.rect, line: item.line)
            )
        }
        store.set(geometry, row: row)
    }
}

/// The selection of a document: from one place to another, across rows. A text row is selected by the character; any other row (code, table, diagram, rule) whole. What is copied is the Markdown the
/// rows were read from where they are selected whole, and the text as shown where a row is selected in part.
@available(macOS 26.0, *)
@MainActor @Observable final class DocumentSelection {
    var anchor: SelectionPoint?
    var focus: SelectionPoint?
    /// The text of each row as written (nil for a row that is not text), and the Markdown it came from.
    @ObservationIgnored private(set) var plain: [String?] = []
    @ObservationIgnored private(set) var source: [String] = []
    @ObservationIgnored let store = GeometryStore()
    /// The frame of each row that is on screen, and where its text starts, in the page's coordinates.
    @ObservationIgnored var frames: [Int: CGRect] = [:]
    @ObservationIgnored var origins: [Int: CGPoint] = [:]
    @ObservationIgnored private var lastClick: (time: TimeInterval, at: CGPoint, count: Int)?

    init(document: NativeDocument) { load(document) }

    /// Reads the rows of a document (when it is another, or drawn with other settings): the selection is cleared.
    func load(_ document: NativeDocument) {
        plain = document.rows.map { row in
            if case .text(let text) = row.content { String(text.string.characters) } else { nil }
        }
        source = document.rows.map(\.source)
        frames = [:]
        origins = [:]
        clear()
    }

    var isEmpty: Bool { start == nil || start == end }
    var start: SelectionPoint? { [anchor, focus].compactMap { $0 }.min() }
    var end: SelectionPoint? { [anchor, focus].compactMap { $0 }.max() }

    func clear() {
        anchor = nil
        focus = nil
    }

    func selectAll() {
        guard let last = plain.indices.last else { return }
        anchor = SelectionPoint(row: 0, offset: 0)
        focus = SelectionPoint(row: last, offset: plain[last]?.utf16.count ?? 1)
    }

    /// The part of a text row that is selected, in UTF-16 units of its text.
    func range(row: Int) -> Range<Int>? {
        guard let start, let end, start != end, row >= start.row, row <= end.row, let text = plain[row] else {
            return nil
        }
        let low = row == start.row ? start.offset : 0
        let high = row == end.row ? end.offset : text.utf16.count
        return low < high ? low ..< high : nil
    }

    /// Whether a row that is not text is selected whole.
    func covers(row: Int) -> Bool {
        guard let start, let end, start != end, plain[row] == nil, row >= start.row, row <= end.row else {
            return false
        }
        return !(row == start.row && start.offset == 1) && !(row == end.row && end.offset == 0)
    }

    // MARK: Pointing

    /// The place a point of the page is at: in the row it is on, or the nearest one.
    func point(at location: CGPoint) -> SelectionPoint? {
        var best: (row: Int, distance: CGFloat)?
        for (row, frame) in frames {
            let distance =
                location.y < frame.minY
                ? frame.minY - location.y : (location.y > frame.maxY ? location.y - frame.maxY : 0)
            if best == nil || distance < best!.distance || (distance == best!.distance && row < best!.row) {
                best = (row, distance)
            }
        }
        guard let row = best?.row, let frame = frames[row] else { return nil }
        if plain[row] != nil, let geometry = store.geometry(row: row), let origin = origins[row],
            let offset = geometry.offset(at: CGPoint(x: location.x - origin.x, y: location.y - origin.y))
        {
            return SelectionPoint(row: row, offset: offset)
        }
        return SelectionPoint(row: row, offset: plain[row] == nil ? (location.y < frame.midY ? 0 : 1) : 0)
    }

    /// A press at `location`: a click starts a selection there, a second click in the same place takes the word, a third the row.
    func press(at location: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        var count = 1
        if let last = lastClick, now - last.time < NSEvent.doubleClickInterval,
            abs(last.at.x - location.x) < 5, abs(last.at.y - location.y) < 5
        {
            count = last.count % 3 + 1
        }
        lastClick = (now, location, count)
        guard let place = point(at: location) else { return clear() }
        anchor = place
        focus = place
        guard let text = plain[place.row] else { return }
        let length = text.utf16.count
        if count == 2 {
            let range = NSAttributedString(string: text)
                .doubleClick(at: Swift.min(place.offset, Swift.max(0, length - 1)))
            if range.length > 0 {
                anchor = SelectionPoint(row: place.row, offset: range.location)
                focus = SelectionPoint(row: place.row, offset: range.location + range.length)
            }
        } else if count == 3 {
            anchor = SelectionPoint(row: place.row, offset: 0)
            focus = SelectionPoint(row: place.row, offset: length)
        }
    }

    /// The pointer moved with the button down: the selection runs from where the press was to here (a word or a row, once taken, stays).
    func drag(to location: CGPoint) {
        guard lastClick?.count == 1, let place = point(at: location) else { return }
        focus = place
    }

    // MARK: Copying

    /// What the selection copies.
    var text: String? {
        guard let start, let end, start != end else { return nil }
        var parts: [String] = []
        for row in start.row ... Swift.min(end.row, plain.count - 1) {
            if let text = plain[row] {
                let length = text.utf16.count
                let low = row == start.row ? start.offset : 0
                let high = row == end.row ? end.offset : length
                guard low < high else { continue }
                if low == 0, high == length {
                    parts.append(source[row].isEmpty ? text : source[row])
                } else if let from = text.utf16.index(
                    text.utf16.startIndex,
                    offsetBy: low,
                    limitedBy: text.utf16.endIndex
                ),
                    let to = text.utf16.index(text.utf16.startIndex, offsetBy: high, limitedBy: text.utf16.endIndex)
                {
                    parts.append(String(text[from ..< to]))
                }
            } else if covers(row: row), !source[row].isEmpty {
                parts.append(source[row])
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

@available(macOS 26.0, *)
extension EnvironmentValues {
    @Entry var documentSelection: DocumentSelection?
}

/// The selected part of a text row, drawn behind its text from the geometry of the last drawing.
@available(macOS 26.0, *)
struct SelectionLayer: View {
    let row: Int
    let selection: DocumentSelection

    var body: some View {
        Canvas { context, _ in
            guard let range = selection.range(row: row), let geometry = selection.store.geometry(row: row) else {
                return
            }
            for box in geometry.boxes(from: range.lowerBound, to: range.upperBound) {
                context.fill(Path(box), with: .color(Color(nsColor: .selectedTextBackgroundColor)))
            }
        }
        .allowsHitTesting(false)
    }
}
