import Foundation

/// A block of the page as the browser laid it out: its tag and class, and its box in points.
struct Block {
    var name: String
    var x: Double, y: Double, width: Double, height: Double

    static func parse(_ json: String) -> [Block] {
        guard let data = json.data(using: .utf8), let list = try? JSONSerialization.jsonObject(with: data) as? [[Any]]
        else { return [] }
        return list.compactMap { item in
            guard item.count == 5, let name = item[0] as? String, let x = item[1] as? Double,
                let y = item[2] as? Double,
                let w = item[3] as? Double, let h = item[4] as? Double
            else { return nil }
            return Block(name: name, x: x, y: y, width: w, height: h)
        }
    }
}

/// A run of rows of the picture that have ink in them: where text lines and boxes are.
struct Band {
    var top: Int, bottom: Int
    var left: Int, right: Int
}

extension Picture {
    func distance(_ x: Int, _ y: Int, from fill: (UInt8, UInt8, UInt8)) -> Int {
        let at = (y * width + x) * 4
        return abs(Int(pixels[at]) - Int(fill.0)) + abs(Int(pixels[at + 1]) - Int(fill.1))
            + abs(Int(pixels[at + 2]) - Int(fill.2))
    }

    /// The bands of ink: rows with a pixel that differs from the fill by more than `threshold`, joined across gaps of `gap` rows or fewer.
    func bands(fill: (UInt8, UInt8, UInt8), threshold: Int = 60, gap: Int = 2) -> [Band] {
        var result: [Band] = []
        var open: Band?
        var blank = 0
        for y in 0 ..< height {
            var first = -1
            var last = -1
            for x in 0 ..< width where distance(x, y, from: fill) > threshold {
                if first < 0 { first = x }
                last = x
            }
            if first >= 0 {
                if var band = open {
                    band.bottom = y
                    band.left = min(band.left, first)
                    band.right = max(band.right, last)
                    open = band
                } else {
                    open = Band(top: y, bottom: y, left: first, right: last)
                }
                blank = 0
            } else if let band = open {
                blank += 1
                if blank > gap {
                    result.append(band)
                    open = nil
                }
            }
        }
        if let band = open { result.append(band) }
        return result
    }

    func blurred(radius: Int = 2) -> Picture {
        var out = self
        var temp = self
        for y in 0 ..< height {
            for x in 0 ..< width {
                for c in 0 ..< 3 {
                    var sum = 0
                    var count = 0
                    for dx in -radius ... radius where x + dx >= 0 && x + dx < width {
                        sum += Int(pixels[(y * width + x + dx) * 4 + c])
                        count += 1
                    }
                    temp.pixels[(y * width + x) * 4 + c] = UInt8(sum / count)
                }
            }
        }
        for y in 0 ..< height {
            for x in 0 ..< width {
                for c in 0 ..< 3 {
                    var sum = 0
                    var count = 0
                    for dy in -radius ... radius where y + dy >= 0 && y + dy < height {
                        sum += Int(temp.pixels[((y + dy) * width + x) * 4 + c])
                        count += 1
                    }
                    out.pixels[(y * width + x) * 4 + c] = UInt8(sum / count)
                }
            }
        }
        return out
    }

    /// Two pictures side by side with their difference (dark on white) in a third panel.
    static func panel(_ a: Picture, _ b: Picture) -> Picture {
        let gap = 8
        let height = max(a.height, b.height)
        var out = Picture(width: a.width * 3 + gap * 2, height: height, fill: (128, 128, 128))
        func put(_ p: Picture, at left: Int) {
            for y in 0 ..< p.height {
                for x in 0 ..< p.width {
                    for c in 0 ..< 3 {
                        out.pixels[(y * out.width + left + x) * 4 + c] = p.pixels[(y * p.width + x) * 4 + c]
                    }
                }
            }
        }
        put(a, at: 0)
        put(b, at: a.width + gap)
        let left = (a.width + gap) * 2
        for y in 0 ..< min(a.height, b.height) {
            for x in 0 ..< a.width {
                var d = 0
                for c in 0 ..< 3 {
                    d += abs(Int(a.pixels[(y * a.width + x) * 4 + c]) - Int(b.pixels[(y * b.width + x) * 4 + c]))
                }
                let level = UInt8(255 - min(255, d))
                let at = (y * out.width + left + x) * 4
                out.pixels[at] = 255
                out.pixels[at + 1] = level
                out.pixels[at + 2] = level
            }
        }
        return out
    }
}

/// How alike two pictures of one size are: the share of the ink (what differs from the fill) that the two have in common, exact and after a blur.
func similarity(_ a: Picture, _ b: Picture, fill: (UInt8, UInt8, UInt8)) -> (exact: Double, blurred: Double) {
    func measure(_ a: Picture, _ b: Picture) -> Double {
        var difference = 0
        var ink = 0
        let fills = [Int(fill.0), Int(fill.1), Int(fill.2)]
        for index in 0 ..< a.width * a.height {
            for channel in 0 ..< 3 {
                let p = Int(a.pixels[index * 4 + channel])
                let q = Int(b.pixels[index * 4 + channel])
                difference += abs(p - q)
                ink += max(abs(p - fills[channel]), abs(q - fills[channel]))
            }
        }
        return ink == 0 ? 1 : 1 - Double(difference) / Double(ink)
    }
    return (measure(a, b), measure(a.blurred(), b.blurred()))
}
