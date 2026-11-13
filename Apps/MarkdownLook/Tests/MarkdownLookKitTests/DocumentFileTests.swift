import AemiIO
import Foundation
import Testing

@testable import MarkdownLookKit

@Suite("Saving a file whole or not at all")
struct DocumentFileTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "atomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func `a new file is written, and nothing else is left beside it`() throws {
        let folder = try folder()
        let file = folder.appending(path: "note.md")
        try DocumentFile.write(Data("# one\n".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "# one\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["note.md"])
    }

    @Test func `an existing file is replaced, and keeps its permissions`() throws {
        let folder = try folder()
        let file = folder.appending(path: "note.md")
        try DocumentFile.write(Data("old".utf8), to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        try DocumentFile.write(Data("new".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "new")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o640)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["note.md"])
    }

    @Test func `a file that cannot be written leaves the old one as it was, and no temporary file`() throws {
        let folder = try folder()
        let file = folder.appending(path: "note.md")
        try DocumentFile.write(Data("kept".utf8), to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        #expect(throws: IOError.self) { try DocumentFile.write(Data("lost".utf8), to: file) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "kept")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["note.md"])
    }

    @Test func `a file through a symbolic link is written where the link points, and the link stays`() throws {
        let folder = try folder()
        let real = folder.appending(path: "real.md")
        let link = folder.appending(path: "link.md")
        try DocumentFile.write(Data("a".utf8), to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try DocumentFile.write(Data("b".utf8), to: link)
        #expect(try String(contentsOf: real, encoding: .utf8) == "b")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
    }
}
