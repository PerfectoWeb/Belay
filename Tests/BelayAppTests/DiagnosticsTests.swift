import XCTest

@testable import Belay

/// The switch is off by default and writes nothing until it is on, which is the
/// whole promise printed next to it.
@MainActor
final class DiagnosticsTests: XCTestCase {
    func testTheFileLivesWhereConsoleLooks() {
        let path = Diagnostics.file.path
        XCTAssertTrue(path.hasSuffix("Library/Logs/Belay/belay.log"), path)
    }

    func testWritingAppendsRatherThanReplaces() throws {
        let file = Diagnostics.file
        try? FileManager.default.createDirectory(
            at: Diagnostics.folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)

        Diagnostics.write("first")
        Diagnostics.write("second")

        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("first"), "the first line was lost")
        XCTAssertTrue(text.contains("second"), "the second line replaced the first")
        XCTAssertEqual(text.split(separator: "\n").count, 2)
        try? FileManager.default.removeItem(at: file)
    }

    func testEveryLineIsStamped() throws {
        let file = Diagnostics.file
        try? FileManager.default.removeItem(at: file)
        Diagnostics.write("something happened")
        let text = try String(contentsOf: file, encoding: .utf8)
        // An ISO stamp, so a report can be lined up against anything else.
        XCTAssertTrue(text.hasPrefix("20"), text)
        XCTAssertTrue(text.contains("T"), text)
        try? FileManager.default.removeItem(at: file)
    }
}
