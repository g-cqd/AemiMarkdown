internal import CoreGraphics
internal import Foundation

@available(macOS 26.0, *)
extension DocumentSelection {
    /// The link under a point of the page, as the page holds it: what its menu is about. Nil beside a link, or over a row
    /// not drawn yet.
    /// - Parameter location: A point in the page's coordinates.
    /// - Returns: The link, or nil.
    func link(at location: CGPoint) -> URL? {
        for (row, frame) in frames where frame.contains(location) {
            guard let origin = origins[row], let geometry = store.geometry(row: row) else { continue }
            let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
            if let link = geometry.links.first(where: { $0.rect.contains(local) }) { return link.url }
        }
        return nil
    }
}
