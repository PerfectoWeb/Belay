import XCTest

@testable import Belay

/// The diagnostics file must not grow forever: past the cap it shrinks to its
/// last megabyte, cut on a line boundary, and says so in its first line.
final class LogTrimTests: XCTestCase {
    private var file: URL!

    override func setUp() {
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent("logtrim-\(UUID().uuidString).log")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file)
    }

    private func writeLines(count: Int) throws {
        var data = Data()
        for i in 0..<count {
            data.append(Data("line \(String(format: "%08d", i)) with some padding text\n".utf8))
        }
        try data.write(to: file)
    }

    func testUnderTheCapIsUntouched() throws {
        try writeLines(count: 1000)
        let before = try Data(contentsOf: file)
        XCTAssertFalse(LogTrim.trimIfOversized(file))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testOversizedShrinksToTheKeptWindow() throws {
        // 100k lines of 37 bytes: ~3.5MB, past the cap.
        try writeLines(count: 100_000)
        XCTAssertTrue(LogTrim.trimIfOversized(file))

        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! Int
        XCTAssertLessThanOrEqual(size, LogTrim.keep + 100)

        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("log trimmed to its last 1MB (was 3.5MB)"))
        // The cut is on a line boundary: the first kept line is whole.
        let lines = text.split(separator: "\n")
        XCTAssertTrue(lines[1].hasPrefix("line "))
        XCTAssertTrue(lines[1].hasSuffix("padding text"))
        // The newest lines survive.
        XCTAssertTrue(lines.last!.contains("line 00099999"))
    }

    func testMissingFileIsNoError() {
        XCTAssertFalse(LogTrim.trimIfOversized(file))
    }
}
