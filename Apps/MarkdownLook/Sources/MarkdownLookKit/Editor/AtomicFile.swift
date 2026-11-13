public import Foundation

/// A file written whole or not at all (ADR-0008): the bytes go to a temporary file beside the destination, are forced to the disk,
/// and take the destination's name in one step, so a crash or a full disk leaves the old file as it was and never half of the new
/// one. A destination that is a symbolic link is written where the link points, and the link stays. The file keeps the permissions
/// it had.
@available(macOS 26.0, *)
public enum AtomicFile {
    /// What could not be done, and the system's error number for it.
    public struct Failure: Error, Equatable, Sendable {
        public enum Step: Sendable, Equatable { case create, write, sync, rename }
        public let step: Step
        public let code: Int32
    }

    /// - Complexity: O(the bytes written), and two waits for the disk (the file, then its folder).
    public static func write(_ data: Data, to url: URL) throws(Failure) {
        let target = url.resolvingSymlinksInPath()
        let folder = target.deletingLastPathComponent()
        let temporary = folder.appending(path: ".\(target.lastPathComponent).\(UUID().uuidString).tmp").path
        let known = try? FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
        let mode = mode_t(known ?? 0o644)
        let descriptor = unsafe open(temporary, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard descriptor >= 0 else { throw Failure(step: .create, code: errno) }
        do throws(Failure) {
            try fill(descriptor, with: data)
            // The mode asked for at creation is cut by the process's mask: set it as the old file had it.
            guard fchmod(descriptor, mode) == 0 else { throw Failure(step: .write, code: errno) }
            // The drive's own cache too, where the drive can; else the system's.
            guard fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0 else {
                throw Failure(step: .sync, code: errno)
            }
            close(descriptor)
            guard unsafe rename(temporary, target.path) == 0 else { throw Failure(step: .rename, code: errno) }
        } catch {
            close(descriptor)
            _ = unsafe unlink(temporary)
            throw error
        }
        // The new name is on the disk once its folder is.
        let entry = unsafe open(folder.path, O_RDONLY)
        if entry >= 0 {
            fsync(entry)
            close(entry)
        }
    }

    private static func fill(_ descriptor: Int32, with data: Data) throws(Failure) {
        var written = 0
        while written < data.count {
            let count = unsafe data.withUnsafeBytes { buffer in
                unsafe Foundation.write(
                    descriptor,
                    buffer.baseAddress.map { unsafe $0 + written },
                    buffer.count - written
                )
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw Failure(step: .write, code: errno) }
            written += count
        }
    }
}
