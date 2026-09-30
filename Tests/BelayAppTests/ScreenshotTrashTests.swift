import XCTest

@testable import Belay

final class ScreenshotTrashTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory
        .appending(path: "belay-trash-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var desk: URL { root.appending(path: "desk", directoryHint: .isDirectory) }
    private var trash: URL { root.appending(path: "trash", directoryHint: .isDirectory) }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: desk, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String, holding text: String) throws -> URL {
        let url = desk.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func text(in name: String) throws -> String {
        try String(contentsOf: trash.appending(path: name), encoding: .utf8)
    }

    func testAFileIsMovedIntoTheTrash() throws {
        let shot = try file("Screenshot.png", holding: "one")

        try ScreenshotTrash.moveByHand(shot, to: trash)

        XCTAssertFalse(FileManager.default.fileExists(atPath: shot.path))
        XCTAssertEqual(try text(in: "Screenshot.png"), "one")
    }

    /// Two captures with one name must both be there afterwards.
    func testANameAlreadyInTheTrashIsNotOverwritten() throws {
        let parts = DateComponents(year: 2026, month: 9, day: 30, hour: 12, minute: 4, second: 9)
        let noon = try XCTUnwrap(Calendar.current.date(from: parts))
        try ScreenshotTrash.moveByHand(try file("Screenshot.png", holding: "one"), to: trash)

        try ScreenshotTrash.moveByHand(try file("Screenshot.png", holding: "two"), to: trash, now: noon)

        XCTAssertEqual(try text(in: "Screenshot.png"), "one")
        XCTAssertEqual(try text(in: "Screenshot 12.04.09.png"), "two")
    }

    func testANameWithoutAnExtensionKeepsNone() throws {
        let parts = DateComponents(year: 2026, month: 9, day: 30, hour: 7, minute: 0, second: 5)
        let morning = try XCTUnwrap(Calendar.current.date(from: parts))
        XCTAssertEqual(
            ScreenshotTrash.renamed(URL(fileURLWithPath: "/desk/Capture"), at: morning),
            "Capture 07.00.05")
    }

    /// A Trash on another volume would be a copy and a delete. The device
    /// filesystem is the one other volume every Mac has.
    func testATrashOnAnotherVolumeIsRefusedAndTheFileStays() throws {
        let shot = try file("Screenshot.png", holding: "one")

        XCTAssertThrowsError(
            try ScreenshotTrash.moveByHand(shot, to: URL(fileURLWithPath: "/dev/fd/trash")))

        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.path))
    }
}
