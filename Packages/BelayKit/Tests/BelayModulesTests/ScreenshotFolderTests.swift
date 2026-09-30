import Foundation
import Testing

@testable import BelayModules

@Suite("Screenshot folder")
struct ScreenshotFolderTests {
    /// A folder of its own per test, under the temporary directory.
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "belay-shots-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func write(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        try Data("pixels".utf8).write(to: url)
        return url
    }

    private func mark(_ url: URL, _ name: String, _ value: Any) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value, format: .binary, options: 0)
        let status = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, $0.count, 0, 0) }
        try #require(status == 0)
    }

    @Test("Only files carrying the capture mark are candidates")
    func markDecides() throws {
        try withFolder { folder in
            let shot = try write("Screenshot 2026-09-29 at 10.00.00.png", in: folder)
            try mark(shot, ScreenshotFolder.captureMark, true)
            // Named like a screenshot and not one: a name is not evidence.
            _ = try write("Screenshot of the contract.png", in: folder)

            let found = try ScreenshotFolder.candidates(in: folder)

            #expect(found.map(\.url.lastPathComponent) == [shot.lastPathComponent])
        }
    }

    @Test("A renamed screenshot is still a screenshot")
    func renameKeepsMark() throws {
        try withFolder { folder in
            let shot = try write("before.png", in: folder)
            try mark(shot, ScreenshotFolder.captureMark, true)
            let renamed = folder.appending(path: "login bug.png")
            try FileManager.default.moveItem(at: shot, to: renamed)

            #expect(try ScreenshotFolder.candidates(in: folder).count == 1)
        }
    }

    @Test("A mark that says no is believed")
    func falseMark() throws {
        try withFolder { folder in
            let file = try write("plain.png", in: folder)
            try mark(file, ScreenshotFolder.captureMark, false)

            #expect(try ScreenshotFolder.candidates(in: folder).isEmpty)
        }
    }

    @Test("Finder tags and recordings are reported")
    func tagsAndRecordings() throws {
        try withFolder { folder in
            let tagged = try write("tagged.png", in: folder)
            try mark(tagged, ScreenshotFolder.captureMark, true)
            try mark(tagged, ScreenshotFolder.tagsMark, ["Red\n6"])
            let film = try write("film.mov", in: folder)
            try mark(film, ScreenshotFolder.captureMark, true)

            let found = try ScreenshotFolder.candidates(in: folder)
                .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }

            #expect(found.map(\.isRecording) == [true, false])
            #expect(found.map(\.isTagged) == [false, true])
        }
    }

    @Test("Subfolders are left alone")
    func notRecursive() throws {
        try withFolder { folder in
            let filed = folder.appending(path: "Keep", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: filed, withIntermediateDirectories: true)
            let shot = try write("filed.png", in: filed)
            try mark(shot, ScreenshotFolder.captureMark, true)

            #expect(try ScreenshotFolder.candidates(in: folder).isEmpty)
        }
    }

    @Test("A folder that is gone throws, so the pass can say so")
    func missingFolder() {
        let gone = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)", isDirectory: true)

        #expect(throws: (any Error).self) { try ScreenshotFolder.candidates(in: gone) }
    }
}
