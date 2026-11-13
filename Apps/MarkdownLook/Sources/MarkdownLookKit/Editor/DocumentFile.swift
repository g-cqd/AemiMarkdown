public import AemiIO
public import Foundation

/// A document's file saved whole or not at all (ADR-0008): Aemi's `AtomicFile` (a temporary file beside the destination, forced
/// to the disk, renamed over it, the folder synced) with what a document someone owns needs besides: a destination that is a
/// symbolic link is written where the link points, so the link stays, and the file keeps the permissions it had.
@available(macOS 26.0, *)
public enum DocumentFile {
    /// - Throws: the failing call's `IOError`; the old file is as it was, and no temporary file is left.
    /// - Complexity: O(the bytes written), and two waits for the disk (the file, then its folder).
    public static func write(_ data: Data, to url: URL) throws(IOError) {
        let target = url.resolvingSymlinksInPath().path
        let known = try? FileManager.default.attributesOfItem(atPath: target)[.posixPermissions] as? Int
        try AtomicFile.replace(at: target, with: Array(data), durability: .full, permissions: UInt16(known ?? 0o644))
    }
}
